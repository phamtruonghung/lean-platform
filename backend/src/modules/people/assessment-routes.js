/*
 * The Assessment half of issue #588's HTTP surface (ADR-0068, slice 3):
 * creating an Assessment, assigning it, and the candidate's own door for
 * starting, answering and submitting one Attempt.
 *
 * Twelve doors under `/api/people`, in two groups.
 *
 * **The Account door** — the register and an Assessment's own record, read by
 * `PPL_ASSESSMENT_DISPLAY` and written by `PPL_ASSESSMENT_CHANGE`:
 *
 *   GET    /assessments                  the register, with its sitting counts
 *   POST   /assessments                  create a draft
 *   GET    /assessments/assign-preview   how many Employees a group reaches
 *   GET    /assessments/:id              the six facts and every Attempt
 *   PATCH  /assessments/:id              correct a draft (a full restatement)
 *   DELETE /assessments/:id              discard a draft
 *   POST   /assessments/:id/assign       expand a group, one Attempt each
 *   POST   /assessments/:id/close        stop new starts
 *
 * **The candidate's own door** — `PPL_ASSESSMENT_SIT`, and always the caller's
 * own Attempt, never somebody else's:
 *
 *   GET    /assessment-attempts/mine               the caller's own Attempts
 *   POST   /assessment-attempts/:id/start          get-or-create the paper
 *   GET    /assessment-attempts/:id                the same paper, on a refresh
 *   PATCH  /assessment-attempts/:id/answers/:position   autosave one Answer
 *   POST   /assessment-attempts/:id/submit         score and finalise
 *
 * `/assessment-attempts/mine` is declared before `/assessment-attempts/:id`
 * for the reason `/training/to-confirm` is: Express matches in declaration
 * order and would read `mine` as an Attempt id.
 *
 * **Writes follow AGENTS.md section 6**: existence first (404), then scope
 * (403), then the body (400). A create or assign asks for the process Org Unit,
 * then `canAct({ write: true })` on it, then the body; a PATCH, DELETE, assign
 * or close asks for the Assessment, then the write reach on its process, then
 * the body. `write: true` is always passed explicitly, because `canAct`
 * defaults it to false and would otherwise authorise a write with a read Grant
 * and no error anywhere.
 *
 * **The key never leaves the server before marking.** No route here returns
 * `correctOption` or `explanation` on a paper; `assessments.js` does not select
 * them, so this file cannot leak what it is never handed.
 *
 * **An Account linked to no Employee** gets a 403 naming that on every door in
 * the candidate group (ADR-0045): "mine" means an Employee's own Attempts, and
 * there is no administrator bypass on a person's own sitting, exactly as
 * `training-routes.js` refuses one on a Trainee's own answer.
 */

const express = require('express');
const { authenticate, requireActive } = require('./middleware');
const authorization = require('./authorization');
const plant = require('./plant');
const assessments = require('./assessments');
const marking = require('./assessment-marking');
const sittings = require('./assessment-sittings');
const { notFound, parseId, handleError, httpError, OUTSIDE_GRANTED_ORG_UNITS } = require('./errors');

const router = express.Router();

const mayReadAssessments = authorization.requirePermission('PPL_ASSESSMENT_DISPLAY');
const mayChangeAssessments = authorization.requirePermission('PPL_ASSESSMENT_CHANGE');
const maySitAssessments = authorization.requirePermission('PPL_ASSESSMENT_SIT');
const mayMarkAssessments = authorization.requirePermission('PPL_ASSESSMENT_MARK');

// handleError answers a message and a code; a thin-bank refusal also carries
// the counts, and a paste-style refusal the line — so the client can say where
// the bank actually is instead of "0 questions everywhere".
function refuse(error, res, next) {
  if (error.status && error.extra) {
    return res.status(error.status).json({ message: error.message, ...error.extra });
  }
  return handleError(error, res, next);
}

function mayWriteAt(account, orgUnitId) {
  return authorization.canAct({ account, orgUnitId, write: true });
}

// `?orgUnitIds=1,2&crewIds=&employeeIds=3` — the create form's live reach. The
// group may be empty (the form starts that way): an empty group reaches nobody,
// which is an answer, not a refusal.
function queryGroup(query) {
  const list = (name) => {
    const raw = query[name];
    if (raw === undefined || raw === null) return [];
    return String(raw)
        .split(',')
        .map((entry) => entry.trim())
        .filter((entry) => entry !== '');
  };
  const read = (name) => {
    const entries = list(name);
    const ids = [];
    for (const entry of entries) {
      if (!/^[1-9][0-9]*$/.test(entry)) throw httpError(400, `${name} must be a comma-separated list of ids`);
      ids.push(entry);
    }
    return ids;
  };
  return { orgUnitIds: read('orgUnitIds'), crewIds: read('crewIds'), employeeIds: read('employeeIds') };
}

// The Assessment (404), then the write reach on the process it draws from
// (403). Answers null once it has already written the refusal.
async function requireWritableAssessment(req, res) {
  const id = parseId(req.params.id);
  const assessment = id === null ? null : await assessments.findAssessment(id);
  if (!assessment) throw notFound('Assessment');
  if (!await mayWriteAt(req.account, assessment.orgUnitId)) {
    res.status(403).json({ message: OUTSIDE_GRANTED_ORG_UNITS });
    return null;
  }
  return assessment;
}

// The candidate's own Employee, or the 403 ADR-0045 prescribes: a sitting is a
// person's own, so an Account linked to no Employee has nothing to sit.
function ownEmployee(req, res) {
  if (req.account.employeeId === null || req.account.employeeId === undefined) {
    res.status(403).json({ message: 'this Account is not linked to an Employee, so it has no Assessment of its own' });
    return null;
  }
  return req.account.employeeId;
}

const NO_EMPLOYEE_MESSAGE =
  'this Account is not linked to an Employee, so it has no Assessment of its own';

// ---------------------------------------------------------------------------
// The register and one Assessment
// ---------------------------------------------------------------------------

router.get('/assessments', authenticate, requireActive, mayReadAssessments, async (req, res, next) => {
  try {
    const orgUnitId = req.query.orgUnitId === undefined ? null : parseId(req.query.orgUnitId);
    if (req.query.orgUnitId !== undefined && orgUnitId === null) {
      throw httpError(400, 'orgUnitId must be a valid Org Unit id');
    }
    if (orgUnitId !== null) await plant.getOrgUnit(orgUnitId); // 404s.

    const status = req.query.status === undefined ? null : req.query.status;
    if (status !== null && !['draft', 'assigned', 'closed'].includes(status)) {
      throw httpError(400, "status must be one of 'draft', 'assigned', 'closed'");
    }
    if (req.query.mine !== undefined && req.query.mine !== 'true' && req.query.mine !== 'false') {
      throw httpError(400, "mine must be 'true' or 'false'");
    }

    const result = await assessments.listAssessments({
      orgUnitId,
      status,
      mine: req.query.mine === 'true',
      accountId: req.account.id
    });
    return res.json(result);
  } catch (error) {
    return refuse(error, res, next);
  }
});

router.post('/assessments', authenticate, requireActive, mayChangeAssessments, async (req, res, next) => {
  try {
    const body = req.body ?? {};
    const orgUnitId = parseId(body.orgUnitId);
    if (orgUnitId === null) throw httpError(400, 'orgUnitId must be a valid Org Unit id');
    const orgUnit = await plant.getOrgUnit(orgUnitId); // 404s.
    if (!await mayWriteAt(req.account, orgUnit.id)) {
      return res.status(403).json({ message: OUTSIDE_GRANTED_ORG_UNITS });
    }

    const facts = assessments.validateAssessmentFacts(body);
    const assessment = await assessments.createAssessment(req.account.id, orgUnit.id, facts);
    return res.status(201).json({ assessment });
  } catch (error) {
    return refuse(error, res, next);
  }
});

// The create form's "will reach N Employees". A read, so it asks DISPLAY and
// nothing else; it writes nothing, and an empty group is a valid question with
// the answer zero. Declared before `/assessments/:id`, or Express would read
// `assign-preview` as an Assessment id.
router.get('/assessments/assign-preview', authenticate, requireActive, mayReadAssessments, async (req, res, next) => {
  try {
    return res.json(await assessments.previewAssign(queryGroup(req.query)));
  } catch (error) {
    return refuse(error, res, next);
  }
});

router.get('/assessments/:id', authenticate, requireActive, mayReadAssessments, async (req, res, next) => {
  try {
    const id = parseId(req.params.id);
    const assessment = id === null ? null : await assessments.findAssessment(id);
    if (!assessment) throw notFound('Assessment');
    // The score fields on the Attempts follow spec section 3.14; the viewer is
    // what carries that answer into the read.
    const viewer = await marking.scoreViewer(req.account);
    return res.json({ assessment: await assessments.getAssessment(id, viewer) });
  } catch (error) {
    return refuse(error, res, next);
  }
});

router.patch('/assessments/:id', authenticate, requireActive, mayChangeAssessments, async (req, res, next) => {
  try {
    const assessment = await requireWritableAssessment(req, res);
    if (!assessment) return undefined;

    const facts = assessments.validateAssessmentFacts(req.body);
    return res.json({ assessment: await assessments.correctAssessment(req.account.id, assessment.id, facts) });
  } catch (error) {
    return refuse(error, res, next);
  }
});

router.delete('/assessments/:id', authenticate, requireActive, mayChangeAssessments, async (req, res, next) => {
  try {
    const assessment = await requireWritableAssessment(req, res);
    if (!assessment) return undefined;

    await assessments.discardAssessment(req.account.id, assessment.id);
    return res.status(204).end();
  } catch (error) {
    return refuse(error, res, next);
  }
});

router.post('/assessments/:id/assign', authenticate, requireActive, mayChangeAssessments, async (req, res, next) => {
  try {
    const assessment = await requireWritableAssessment(req, res);
    if (!assessment) return undefined;

    const group = assessments.validateGroup(req.body);
    const result = await assessments.assignAssessment(req.account.id, assessment, group);
    return res.status(201).json({
      assigned: result.assigned,
      assessment: await assessments.getAssessment(
        assessment.id,
        await marking.scoreViewer(req.account)
      )
    });
  } catch (error) {
    return refuse(error, res, next);
  }
});

router.post('/assessments/:id/close', authenticate, requireActive, mayChangeAssessments, async (req, res, next) => {
  try {
    const assessment = await requireWritableAssessment(req, res);
    if (!assessment) return undefined;

    await assessments.closeAssessment(req.account.id, assessment.id);
    return res.json({
      assessment: await assessments.getAssessment(
        assessment.id,
        await marking.scoreViewer(req.account)
      )
    });
  } catch (error) {
    return refuse(error, res, next);
  }
});

// A Team Leader's "End sitting" (slice 5, spec 7.1): revokes the floor sitting
// token so the candidate's next request is a 401 and they continue only by
// identifying again. The Attempt keeps running on the server's clock. Existence
// (404), then write reach on the Attempt's own Org Unit (403), then whether a
// sitting exists at all (404).
router.post('/assessment-attempts/:id/end-sitting', authenticate, requireActive, mayChangeAssessments, async (req, res, next) => {
  try {
    const id = parseId(req.params.id);
    const attempt = id === null ? null : await sittings.findAttemptScope(id);
    if (!attempt) throw notFound('Assessment attempt');
    if (!await mayWriteAt(req.account, attempt.orgUnitId)) {
      return res.status(403).json({ message: OUTSIDE_GRANTED_ORG_UNITS });
    }
    if (!await sittings.endSitting(req.account.id, attempt.id)) throw notFound('Sitting');
    return res.json({ ended: true });
  } catch (error) {
    return refuse(error, res, next);
  }
});

// ---------------------------------------------------------------------------
// The candidate's own door
// ---------------------------------------------------------------------------

// Declared before `/assessment-attempts/:id` — see this file's header.
router.get('/assessment-attempts/mine', authenticate, requireActive, maySitAssessments, async (req, res, next) => {
  try {
    if (req.account.employeeId === null || req.account.employeeId === undefined) {
      return res.status(403).json({ message: NO_EMPLOYEE_MESSAGE });
    }
    const attempts = await assessments.listMyAttempts(req.account.employeeId);
    return res.json({ attempts });
  } catch (error) {
    return refuse(error, res, next);
  }
});

router.post('/assessment-attempts/:id/start', authenticate, requireActive, maySitAssessments, async (req, res, next) => {
  try {
    const mine = ownEmployee(req, res);
    if (mine === null) return undefined;

    const id = parseId(req.params.id);
    if (id === null) throw notFound('Assessment attempt');
    return res.json(await assessments.startAttempt(req.account.id, id, mine));
  } catch (error) {
    return refuse(error, res, next);
  }
});

router.get('/assessment-attempts/:id', authenticate, requireActive, maySitAssessments, async (req, res, next) => {
  try {
    const mine = ownEmployee(req, res);
    if (mine === null) return undefined;

    const id = parseId(req.params.id);
    if (id === null) throw notFound('Assessment attempt');
    return res.json(await assessments.getAttempt(id, mine));
  } catch (error) {
    return refuse(error, res, next);
  }
});

router.patch('/assessment-attempts/:id/answers/:position', authenticate, requireActive, maySitAssessments, async (req, res, next) => {
  try {
    const mine = ownEmployee(req, res);
    if (mine === null) return undefined;

    const id = parseId(req.params.id);
    if (id === null) throw notFound('Assessment attempt');
    const position = Number(req.params.position);
    if (!Number.isInteger(position) || position < 1 || position > 15) {
      throw httpError(400, 'position must be a whole number between 1 and 15');
    }

    const answer = assessments.validateAnswer(req.body);
    return res.json(await assessments.saveAnswer(req.account.id, id, mine, position, answer));
  } catch (error) {
    return refuse(error, res, next);
  }
});

router.post('/assessment-attempts/:id/submit', authenticate, requireActive, maySitAssessments, async (req, res, next) => {
  try {
    const mine = ownEmployee(req, res);
    if (mine === null) return undefined;

    const id = parseId(req.params.id);
    if (id === null) throw notFound('Assessment attempt');
    return res.json(await assessments.submitAttempt(req.account.id, id, mine));
  } catch (error) {
    return refuse(error, res, next);
  }
});

// ---------------------------------------------------------------------------
// Marking, and the result (issue #588, slice 4)
// ---------------------------------------------------------------------------

// The queue of `submitted` Attempts in the caller's write reach, oldest first.
// A read of the caller's own work, so the reach is asked in SQL from the
// caller's own Grants; `orgUnitId` narrows to one process, and a process the
// caller's write Grants do not reach is a 403 (existence first, then scope).
router.get('/assessment-marking', authenticate, requireActive, mayMarkAssessments, async (req, res, next) => {
  try {
    const orgUnitId = req.query.orgUnitId === undefined ? null : parseId(req.query.orgUnitId);
    if (req.query.orgUnitId !== undefined && orgUnitId === null) {
      throw httpError(400, 'orgUnitId must be a valid Org Unit id');
    }
    if (orgUnitId !== null) {
      await plant.getOrgUnit(orgUnitId); // 404s.
      if (!await mayWriteAt(req.account, orgUnitId)) throw httpError(403, OUTSIDE_GRANTED_ORG_UNITS);
    }

    return res.json(await marking.markingQueue(req.account, { orgUnitId }));
  } catch (error) {
    return refuse(error, res, next);
  }
});

// The paper with its key, its points and the candidate's Answers. Existence
// first (404), then the reach (403) — inside the service file, because the
// reach is a question about the Attempt's two Org Units rather than about an id
// in the path.
router.get('/assessment-attempts/:id/marking', authenticate, requireActive, mayMarkAssessments, async (req, res, next) => {
  try {
    const id = parseId(req.params.id);
    if (id === null) throw notFound('Assessment attempt');
    return res.json(await marking.readMarkingPaper(req.account, id));
  } catch (error) {
    return refuse(error, res, next);
  }
});

// The award. `{ answers: [{ position, points, note? }], note }`; a second call
// on a marked Attempt is a 409, because an award is a record and not a form
// somebody may edit twice.
router.post('/assessment-attempts/:id/mark', authenticate, requireActive, mayMarkAssessments, async (req, res, next) => {
  try {
    const id = parseId(req.params.id);
    if (id === null) throw notFound('Assessment attempt');
    return res.json(await marking.markAttempt(req.account, id, req.body));
  } catch (error) {
    return refuse(error, res, next);
  }
});

// The result: 409 until the Attempt is marked, then the score, the derived
// verdict and every Question with the key and the explanation. Gated on
// `DISPLAY` — the code that opens the register a result is reached from — and
// narrowed inside the service to the two callers who may read it: the person
// whose Attempt it is (holding `SIT` or `DISPLAY`), and the readers of spec
// section 3.14 (admin, or `MARK`/`CHANGE` with write reach).
router.get('/assessment-attempts/:id/result', authenticate, requireActive, mayReadAssessments, async (req, res, next) => {
  try {
    const id = parseId(req.params.id);
    if (id === null) throw notFound('Assessment attempt');
    return res.json(await marking.readResult(req.account, id));
  } catch (error) {
    return refuse(error, res, next);
  }
});

module.exports = router;
