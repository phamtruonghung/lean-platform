/*
 * The Training record's HTTP surface (issue #287, ADR-0043). training.js owns
 * the SQL, the row shape and the validation of a record's own facts; this file
 * owns Express, the scope question and the error mapping.
 *
 * Writes follow AGENTS.md section 6's order — existence first, then scope —
 * so an administrator's typo is a 404, never a 500: required fields (400),
 * the Org Unit (404), the trainer Employee (404), then
 * `canAct({ write: true })` (403). Correcting (#291) is a full restatement of
 * the record's facts, draft or sent alike, validated by the raise route's own
 * `validateRaise`: the record (404), its scope (403), then the body (400) and
 * the trainer Employee (404). There is no status refusal any more.
 *
 * Discarding (#291), `DELETE /training/:id`: the record (404), its scope
 * (403), then a sent record (409 - sending is where a record becomes
 * evidence); a draft is deleted with its Trainee rows, answering 204.
 *
 * Reads: the register answers every approved Account, as ADR-0009 says of a
 * read, but a draft is shown only to a caller who could send it (an edit
 * Grant reaching its Org Unit, or an administrator) — the same predicate as
 * the write check. A draft the caller could not send reads as a 404 at its
 * own address rather than a 403, so the register is not a way to learn a
 * draft exists.
 *
 * The Trainees (#288, #291): adding and removing one follow the same order —
 * the record (404), its scope (403), then the body (400), the Employee (404),
 * a departed Employee (409, as assigning a Work order to one is refused) and
 * the write; removal asks for the Trainee on THIS record (404). Both are legal
 * on a sent record: an added Trainee is asked at once, and a removed one takes
 * their answer with the row. Both answer with the fresh whole record, Trainees
 * included.
 *
 * Sending (#289): the record (404), its scope (403, the same edit Grant as
 * every other write, `write: true` explicit), already sent (409), then the
 * record's completeness (409, in the Module's own words — the request is
 * well formed and it is the record's state that refuses it).
 *
 * A Trainee's evaluation (#290) is the trainer's own field, settable after
 * sending: the record (404), its scope (403), the body (400), the Trainee (404).
 *
 * A Trainee's answer (#289) is the one write here with no Grant question at
 * all: the caller must BE the Trainee, i.e. the Employee their own Account is
 * linked to (`app_users.employee_id`). Not even an administrator holding an
 * edit Grant may answer for anyone — an answer is a person's own signature.
 * The order: the answer value (400), the Trainee row (404), whose it is (403),
 * a record not yet sent (404), then the write. The optional `signature`
 * (#318) is `{ use: "stored" }` or `{ image }`, validated with the answer
 * value (400, a decline carrying one included); `stored` resolves the caller's
 * own current Signature and `image` writes a one-off row for the caller's own
 * Employee, so no Signature id is ever taken from the request.
 */

const express = require('express');
const { authenticate, requireActive } = require('./middleware');
const authorization = require('./authorization');
const plant = require('./plant');
const directory = require('./directory');
const training = require('./training');
const { parseApplied } = require('./signatures');
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

    const facts = training.validateRaise(req.body ?? {});
    await requireKnownTrainer(facts.trainerEmployeeId);
    const corrected = await training.correctTrainingRecord(req.account.id, record.id, facts);
    return res.json({ trainingRecord: corrected });
  } catch (error) {
    return handleError(error, res, next);
  }
});

// Resolves the record and checks its scope, the order every Trainee write
// shares. Returns the record, or null when it has already answered 403.
async function resolveRecordForTrainees(req, res) {
  const record = await training.getTrainingRecord(req.params.id); // 404s.
  const allowed = await authorization.canAct({
    account: req.account,
    orgUnitId: record.orgUnitId,
    write: true
  });
  if (!allowed) {
    res.status(403).json({ message: OUTSIDE_GRANTED_ORG_UNITS });
    return null;
  }
  return record;
}

router.delete('/training/:id', authenticate, requireActive, async (req, res, next) => {
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

    await training.discardTrainingRecord(req.account.id, record.id); // 409s a sent record.
    return res.status(204).end();
  } catch (error) {
    return handleError(error, res, next);
  }
});

router.post('/training/:id/trainees', authenticate, requireActive, async (req, res, next) => {
  try {
    const record = await resolveRecordForTrainees(req, res);
    if (record === null) return undefined;

    const employeeId = parseId(req.body?.employeeId);
    if (employeeId === null) throw httpError(400, 'employeeId must be a valid Employee id');
    const employee = await directory.findEmployee(employeeId);
    if (!employee) throw notFound('Employee');
    if (!employee.isActive) {
      throw httpError(409, 'this Employee has departed and cannot be added as a Trainee');
    }

    const updated = await training.addTrainee(req.account.id, record.id, employeeId);
    return res.status(201).json({ trainingRecord: updated });
  } catch (error) {
    return handleError(error, res, next);
  }
});

router.delete('/training/:id/trainees/:traineeId', authenticate, requireActive, async (req, res, next) => {
  try {
    const record = await resolveRecordForTrainees(req, res);
    if (record === null) return undefined;

    const trainee = await training.findTrainee(record.id, req.params.traineeId);
    if (!trainee) throw notFound('Trainee');

    const updated = await training.removeTrainee(req.account.id, record.id, trainee.id);
    return res.json({ trainingRecord: updated });
  } catch (error) {
    return handleError(error, res, next);
  }
});

// The trainer's own field, so unlike add and remove it is allowed on a sent
// record as well as a draft: the record (404), its scope (403), the body (400),
// then the Trainee on THIS record (404).
router.patch('/training/:id/trainees/:traineeId', authenticate, requireActive, async (req, res, next) => {
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

    const evaluation = training.requireEvaluation(req.body);
    const trainee = await training.findTrainee(record.id, req.params.traineeId);
    if (!trainee) throw notFound('Trainee');

    const updated = await training.setTraineeEvaluation(req.account.id, record.id, trainee.id, evaluation);
    return res.json({ trainingRecord: updated });
  } catch (error) {
    return handleError(error, res, next);
  }
});

router.post('/training/:id/send', authenticate, requireActive, async (req, res, next) => {
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
    if (record.status === 'sent') {
      throw httpError(409, 'This Training record has already been sent');
    }
    const missing = training.incompleteness(record);
    if (missing !== null) throw httpError(409, missing);

    const sent = await training.sendTrainingRecord(req.account.id, record.id);
    return res.json({ trainingRecord: sent });
  } catch (error) {
    return handleError(error, res, next);
  }
});

router.post('/training/trainees/:traineeId/answer', authenticate, requireActive, async (req, res, next) => {
  try {
    const answer = training.requireAnswer(req.body?.answer);
    const applied = parseApplied(req.body?.signature);
    if (applied !== null && answer === 'declined') {
      throw httpError(400, 'a declined answer carries no Signature');
    }
    const trainee = await training.findTraineeForAnswer(req.params.traineeId);
    if (!trainee) throw notFound('Trainee');

    // "Not yours" is a 403, not a 404: the row exists and the caller is told
    // plainly that an answer is the Trainee's own. An Account linked to no
    // Employee is refused the same way. No administrator bypass.
    if (req.account.employeeId === null || String(trainee.employeeId) !== String(req.account.employeeId)) {
      return res.status(403).json({ message: 'Only the Trainee can answer for themselves' });
    }
    // The one place the order bends: a draft is not yet a fact to its Trainees,
    // so, like the detail read of a draft, it is a 404 and not a 409.
    if (trainee.recordStatus !== 'sent') throw notFound('Trainee');

    const updated = await training.answerTrainee(
      req.account.id,
      req.account.employeeId,
      trainee.id,
      answer,
      applied
    );
    return res.json({ trainingRecord: updated });
  } catch (error) {
    return handleError(error, res, next);
  }
});

// The Signature applied to a Trainee's answer, as the image itself. Under the
// record's own read rule (any approved Account, ADR-0009 and ADR-0052): a
// Signature is not a secret, and this is the only door that returns one.
router.get('/training/trainees/:traineeId/signature', authenticate, requireActive, async (req, res, next) => {
  try {
    const image = await training.getTraineeSignatureImage(req.params.traineeId);
    res.set('Cache-Control', 'private, no-cache');
    return res.type('image/png').send(image);
  } catch (error) {
    return handleError(error, res, next);
  }
});

// Declared before GET /training/:id on purpose: Express matches in
// declaration order, so the other order reads `to-confirm` as a record id.
router.get('/training/to-confirm', authenticate, requireActive, async (req, res, next) => {
  try {
    // A caller whose Account is linked to no Employee has nothing waiting on
    // them: an empty list, not an error.
    const trainingToConfirm = await training.listTrainingToConfirm(req.account.employeeId ?? null);
    return res.json({ trainingToConfirm });
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

    let siteId = null;
    if (req.query.siteId !== undefined) {
      if (parseId(req.query.siteId) === null) {
        throw httpError(400, 'siteId must be a valid Site id');
      }
      siteId = (await plant.getSite(req.query.siteId)).id; // 404s.
    }

    const { trainingRecords, truncated } = await training.listTrainingRecords({
      viewer: { accountId: req.account.id, isAdmin: authorization.isAdmin(req.account) },
      siteId,
      orgUnitPath,
      from,
      to
    });
    return res.json({ trainingRecords, truncated });
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
