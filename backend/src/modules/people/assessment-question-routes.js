/*
 * The assessment Question bank's HTTP surface (issue #588, ADR-0068, slice 2).
 * assessment-questions.js owns the SQL, the row shape, the validation of a
 * Question's own fields and the paste parser; this file owns Express, the
 * permission codes, the scope question and the error mapping.
 *
 * Five doors under `/api/people`. Every one runs `authenticate`,
 * `requireActive`, then its code (ADR-0061, the code says what, the Grant says
 * where): the read asks `PPL_ASSESSMENT_DISPLAY`, the four writes ask
 * `PPL_ASSESSMENT_CHANGE`.
 *
 *   GET    /assessment-questions        one process's bank, paged, with counts
 *   POST   /assessment-questions        raise one Question
 *   POST   /assessment-questions/bulk   the paste, all-or-nothing
 *   PATCH  /assessment-questions/:id    correct one Question (a full restatement)
 *   DELETE /assessment-questions/:id    retire it; a Question is never removed
 *
 * `/bulk` is a POST and `/:id` is only PATCH and DELETE, so the literal path
 * cannot be swallowed; it is still declared first so nobody adds a POST
 * `/:id` below it by mistake.
 *
 * Writes follow AGENTS.md section 6, existence first and then scope, and the
 * body last so an administrator's typo is a 404 and nobody learns what a body
 * should look like for an Org Unit they may not touch: a create or paste asks
 * for the Org Unit (404), then `canAct({ write: true })` (403), then the body
 * (400). A PATCH or DELETE asks for the Question (404), then its Org Unit's
 * scope (403); a PATCH then refuses a retired Question (409, there is no way
 * back to active in this slice) before it reads the body (400).
 *
 * The key and explanation are read-sensitive: they are returned only to a
 * caller who holds `PPL_ASSESSMENT_CHANGE` AND has write reach on the Org
 * Unit asked about, evaluated once per request. Everyone else with `DISPLAY`
 * sees the Questions and Options, the counts, and `null` in their place. That
 * restricts a field, not the list: the bank stays readable plant-wide
 * (ADR-0009) and `includeInactive` needs `DISPLAY` alone.
 *
 * The paste is all-or-nothing: a malformed block, a block repeating an
 * earlier one, or a block already in the bank refuses the whole paste and
 * writes nothing, because a half-imported bank is worse than none - the author
 * could not tell which half is in. The refusal names the line.
 */

const express = require('express');
const { authenticate, requireActive } = require('./middleware');
const authorization = require('./authorization');
const plant = require('./plant');
const roles = require('./roles');
const questions = require('./assessment-questions');
const { notFound, parseId, handleError, httpError, OUTSIDE_GRANTED_ORG_UNITS } = require('./errors');

const router = express.Router();

const mayReadBank = authorization.requirePermission('PPL_ASSESSMENT_DISPLAY');
const mayChangeBank = authorization.requirePermission('PPL_ASSESSMENT_CHANGE');

// handleError answers a message and a code; a paste refusal also carries the
// line (and the other line or the existing Question) so a client can point at it.
function refuse(error, res, next) {
  if (error.status && error.extra) {
    return res.status(error.status).json({ message: error.message, ...error.extra });
  }
  return handleError(error, res, next);
}

function mayWriteAt(account, orgUnitId) {
  return authorization.canAct({ account, orgUnitId, write: true });
}

router.get('/assessment-questions', authenticate, requireActive, mayReadBank, async (req, res, next) => {
  try {
    const orgUnitId = parseId(req.query.orgUnitId);
    if (orgUnitId === null) throw httpError(400, 'orgUnitId must be a valid Org Unit id');
    const orgUnit = await plant.getOrgUnit(orgUnitId); // 404s.

    const { includeInactive } = req.query;
    if (includeInactive !== undefined && includeInactive !== 'true' && includeInactive !== 'false') {
      throw httpError(400, "includeInactive must be 'true' or 'false'");
    }

    const held = await roles.effectivePermissions(req.account);
    const revealKey = held.some((row) => row.code === 'PPL_ASSESSMENT_CHANGE')
      && await mayWriteAt(req.account, orgUnit.id);

    const result = await questions.listQuestions({
      orgUnitId: orgUnit.id,
      q: typeof req.query.q === 'string' ? req.query.q : undefined,
      includeInactive: includeInactive === 'true',
      limit: req.query.limit,
      offset: req.query.offset,
      revealKey
    });
    return res.json(result);
  } catch (error) {
    return refuse(error, res, next);
  }
});

router.post('/assessment-questions/bulk', authenticate, requireActive, mayChangeBank, async (req, res, next) => {
  try {
    const body = req.body ?? {};
    const orgUnitId = parseId(body.orgUnitId);
    if (orgUnitId === null) throw httpError(400, 'orgUnitId must be a valid Org Unit id');
    const orgUnit = await plant.getOrgUnit(orgUnitId); // 404s.
    if (!await mayWriteAt(req.account, orgUnit.id)) {
      return res.status(403).json({ message: OUTSIDE_GRANTED_ORG_UNITS });
    }

    if (typeof body.text !== 'string') throw httpError(400, 'text is required');
    const parsed = questions.parsePaste(body.text);
    if (parsed.error) {
      const payload = { message: parsed.error.message };
      if (parsed.error.line !== null) payload.line = parsed.error.line;
      return res.status(400).json(payload);
    }

    const created = await questions.bulkCreateQuestions(req.account.id, orgUnit.id, parsed.questions);
    return res.status(201).json({ created: created.length, questions: created });
  } catch (error) {
    return refuse(error, res, next);
  }
});

router.post('/assessment-questions', authenticate, requireActive, mayChangeBank, async (req, res, next) => {
  try {
    const body = req.body ?? {};
    const orgUnitId = parseId(body.orgUnitId);
    if (orgUnitId === null) throw httpError(400, 'orgUnitId must be a valid Org Unit id');
    const orgUnit = await plant.getOrgUnit(orgUnitId); // 404s.
    if (!await mayWriteAt(req.account, orgUnit.id)) {
      return res.status(403).json({ message: OUTSIDE_GRANTED_ORG_UNITS });
    }

    const facts = questions.validateQuestion(body);
    const question = await questions.createQuestion(req.account.id, orgUnit.id, facts);
    return res.status(201).json({ question });
  } catch (error) {
    return refuse(error, res, next);
  }
});

// The Question (404), then the scope of its own Org Unit (403). Answers null
// once it has already written the 404/403, so the caller just returns.
async function requireWritableQuestion(req, res) {
  const id = parseId(req.params.id);
  const question = id === null ? null : await questions.findQuestion(id);
  if (!question) throw notFound('Question');
  if (!await mayWriteAt(req.account, question.orgUnitId)) {
    res.status(403).json({ message: OUTSIDE_GRANTED_ORG_UNITS });
    return null;
  }
  return question;
}

router.patch('/assessment-questions/:id', authenticate, requireActive, mayChangeBank, async (req, res, next) => {
  try {
    const question = await requireWritableQuestion(req, res);
    if (!question) return undefined;
    if (!question.isActive) {
      throw httpError(409, 'this Question is retired and cannot be corrected');
    }

    const facts = questions.validateQuestion(req.body);
    const corrected = await questions.correctQuestion(req.account.id, question, facts);
    return res.json({ question: corrected });
  } catch (error) {
    return refuse(error, res, next);
  }
});

router.delete('/assessment-questions/:id', authenticate, requireActive, mayChangeBank, async (req, res, next) => {
  try {
    const question = await requireWritableQuestion(req, res);
    if (!question) return undefined;

    await questions.retireQuestion(req.account.id, question.id);
    return res.status(204).end();
  } catch (error) {
    return refuse(error, res, next);
  }
});

module.exports = router;
