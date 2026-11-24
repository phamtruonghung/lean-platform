/*
 * An Employee sitting an Assessment at the shared floor device (issue #588,
 * ADR-0068, slice 5; spec sections 4.6, 7.2 and 9.1): the second door onto the
 * same Attempt `assessment-routes.js` gives an Account. Most of a plant holds no
 * Account, so an Employee identifies at the device with their number and PIN,
 * starts their own Attempt, and then answers it for as long as it runs.
 *
 * Six routes, on the frozen `/api/maintenance` prefix the deployed devices are
 * pointed at (#201) - composed into `floorRouter` by index.js beside
 * floor-training-routes.js:
 *
 *   - GET   /floor/assessments/mine                          identification
 *   - POST  /floor/assessments/:attemptId/start              identification
 *   - GET   /floor/assessments/:attemptId                    sitting
 *   - PATCH /floor/assessments/:attemptId/answers/:position  sitting
 *   - POST  /floor/assessments/:attemptId/submit             sitting
 *   - GET   /floor/assessments/:attemptId/result             sitting or identification
 *
 * **Two credentials, and why.** The 120-second identification
 * (`x-technician-identification`) decides who may START and who may read their
 * own result days later. A paper runs 20 or 30 minutes, so once started it is
 * answered under a sitting token (`x-assessment-sitting`), minted by `start`,
 * stored only as its SHA-256 and bound to (Attempt, device). The identification
 * is NOT accepted on the sitting routes: a second Employee identifying on the
 * same device neither stops the first sitting nor can touch it.
 *
 * **Binding order** (spec 7.2). `x-floor-device` (401); on the identification
 * routes the identification (401 missing, expired or issued to another device),
 * then the Attempt (404), then the device's reach of the Attempt's own Org Unit
 * (403 with OUTSIDE_GRANTED_ORG_UNITS), then the Attempt being the identified
 * Employee's own (403). On the sitting routes the token (401 on any miss: wrong
 * Attempt, wrong device, revoked, expired, unknown), then the reach again,
 * because a device may be moved or its Org Unit rearranged mid-paper. Existence
 * before scope, AGENTS.md section 6.
 *
 * The paper itself is `assessments.js`'s and the result `assessment-marking.js`'s,
 * called exactly as the Account door calls them, so the two doors cannot
 * disagree about the key never leaving before marking. There is no Account on
 * this path, so the audit carries none (floor-training-routes.js does the same).
 *
 * **No permission code on this door (ADR-0061, slice 5b; re-examined in phase
 * 2d).** The Account door asks `PPL_ASSESSMENT_SIT`; this door asks a device
 * credential and an individual identification (or a sitting token minted behind
 * one) instead, with no Account anywhere on the path, so there is no role to
 * read and nothing for `requirePermission` to ask - it reads the permissions of
 * `req.account`, and `req.account` does not exist here. The identification IS
 * this door's authority, it is the identified Employee's own, and the identity
 * check below still confines the write to their own Attempt; adding a code in
 * front of it would answer 500 or 403 to every sitting a tablet in the plant
 * sends. The same split floor-training-routes.js settled for its own pair.
 */

const express = require('express');
const floorDevices = require('./floor-devices');
const assessments = require('./assessments');
const marking = require('./assessment-marking');
const sittings = require('./assessment-sittings');
const { requireFloorDevice } = require('./floor-device-middleware');
const { notFound, parseId, httpError, handleError, OUTSIDE_GRANTED_ORG_UNITS } = require('./errors');

const router = express.Router();

const OPEN = ['assigned', 'in_progress'];

// Same wording as floor-training-routes.js.
async function requireTechnicianIdentification(req, res, next) {
  try {
    const token = req.headers['x-technician-identification'];
    if (typeof token !== 'string' || token === '') {
      return res
        .status(401)
        .json({ message: 'An individual identification is required to write here' });
    }
    const technician = await floorDevices.findValidIdentification(token, req.floorDevice.id);
    if (!technician) {
      return res.status(401).json({ message: 'This identification is invalid or has expired' });
    }
    req.technician = technician;
    return next();
  } catch (error) {
    return handleError(error, res, next);
  }
}

function refuse(error, res, next) {
  if (error.status && error.extra) {
    return res.status(error.status).json({ message: error.message, ...error.extra });
  }
  return handleError(error, res, next);
}

// The sitting token for `:attemptId`, or the one 401 for every way it can fail.
async function sittingOf(req) {
  const attemptId = parseId(req.params.attemptId);
  if (attemptId === null) return null;
  return sittings.findValidSitting(req.headers['x-assessment-sitting'], attemptId, req.floorDevice.id);
}

const SITTING_REFUSAL = { message: 'This sitting is invalid or has ended; identify again to continue' };

// The reach check both doors repeat on every call. Returns false after writing
// the 403.
async function deviceReaches(req, res, attempt) {
  const reaches = await floorDevices.deviceReachesOrgUnit(req.floorDevice.orgUnitId, attempt.orgUnitId);
  if (!reaches) {
    res.status(403).json({ message: OUTSIDE_GRANTED_ORG_UNITS });
    return false;
  }
  return true;
}

// Identification routes: the Attempt (404), the device's reach (403), then the
// Attempt being the identified Employee's own (403). Null after writing.
async function requireOwnAttemptByIdentification(req, res) {
  const attemptId = parseId(req.params.attemptId);
  const attempt = attemptId === null ? null : await sittings.findAttemptScope(attemptId);
  if (!attempt) throw notFound('Assessment attempt');
  if (!await deviceReaches(req, res, attempt)) return null;
  if (String(attempt.employeeId) !== String(req.technician.id)) {
    res.status(403).json({ message: assessments.NOT_YOURS });
    return null;
  }
  return attempt;
}

// Sitting routes: the token (401), then the reach (403). Returns the sitting's
// Employee, or null after writing.
async function requireSitting(req, res) {
  const sitting = await sittingOf(req);
  if (!sitting) {
    res.status(401).json(SITTING_REFUSAL);
    return null;
  }
  const attempt = await sittings.findAttemptScope(parseId(req.params.attemptId));
  if (!attempt) throw notFound('Assessment attempt');
  if (!await deviceReaches(req, res, attempt)) return null;
  return { attemptId: attempt.id, employeeId: sitting.employeeId };
}

// Declared before `/floor/assessments/:attemptId`, as `mine` would otherwise be
// read as an Attempt id.
router.get(
  '/floor/assessments/mine',
  requireFloorDevice,
  requireTechnicianIdentification,
  async (req, res, next) => {
    try {
      const all = await assessments.listMyAttempts(req.technician.id);
      const attempts = [];
      for (const attempt of all) {
        if (!OPEN.includes(attempt.status)) continue;
        if (await floorDevices.deviceReachesOrgUnit(req.floorDevice.orgUnitId, attempt.orgUnitId)) {
          attempts.push(attempt);
        }
      }
      return res.json({ attempts });
    } catch (error) {
      return refuse(error, res, next);
    }
  }
);

router.post(
  '/floor/assessments/:attemptId/start',
  requireFloorDevice,
  requireTechnicianIdentification,
  async (req, res, next) => {
    try {
      const attempt = await requireOwnAttemptByIdentification(req, res);
      if (!attempt) return undefined;

      const started = await assessments.startAttempt(null, attempt.id, req.technician.id);
      const sittingToken = await sittings.mintSitting({
        attemptId: attempt.id,
        employeeId: req.technician.id,
        deviceId: req.floorDevice.id
      });
      // The Account door's own body (`attempt`, `paper`, `serverNow`) plus the
      // spec's `assessment` and `deadlineAt` names, so either reading works.
      return res.json({
        ...started,
        assessment: started.attempt,
        paper: started.paper,
        deadlineAt: started.attempt.deadlineAt,
        serverNow: started.serverNow,
        sittingToken
      });
    } catch (error) {
      return refuse(error, res, next);
    }
  }
);

router.get('/floor/assessments/:attemptId', requireFloorDevice, async (req, res, next) => {
  try {
    const sitting = await requireSitting(req, res);
    if (!sitting) return undefined;
    return res.json(await assessments.getAttempt(sitting.attemptId, sitting.employeeId));
  } catch (error) {
    return refuse(error, res, next);
  }
});

router.patch('/floor/assessments/:attemptId/answers/:position', requireFloorDevice, async (req, res, next) => {
  try {
    const sitting = await requireSitting(req, res);
    if (!sitting) return undefined;

    const position = Number(req.params.position);
    if (!Number.isInteger(position) || position < 1 || position > 15) {
      throw httpError(400, 'position must be a whole number between 1 and 15');
    }
    const answer = assessments.validateAnswer(req.body);
    return res.json(
      await assessments.saveAnswer(null, sitting.attemptId, sitting.employeeId, position, answer)
    );
  } catch (error) {
    return refuse(error, res, next);
  }
});

router.post('/floor/assessments/:attemptId/submit', requireFloorDevice, async (req, res, next) => {
  try {
    const sitting = await requireSitting(req, res);
    if (!sitting) return undefined;
    return res.json(await assessments.submitAttempt(null, sitting.attemptId, sitting.employeeId));
  } catch (error) {
    return refuse(error, res, next);
  }
});

// The sitting token, or else the identification: a result read days later,
// after the sitting has expired, is a fresh number and PIN.
router.get('/floor/assessments/:attemptId/result', requireFloorDevice, async (req, res, next) => {
  try {
    let employeeId;
    let attemptId;
    if (typeof req.headers['x-assessment-sitting'] === 'string' && req.headers['x-assessment-sitting'] !== '') {
      const sitting = await requireSitting(req, res);
      if (!sitting) return undefined;
      ({ employeeId, attemptId } = sitting);
    } else {
      const token = req.headers['x-technician-identification'];
      if (typeof token !== 'string' || token === '') {
        return res.status(401).json({ message: 'An identification or a sitting is required to read this' });
      }
      const technician = await floorDevices.findValidIdentification(token, req.floorDevice.id);
      if (!technician) {
        return res.status(401).json({ message: 'This identification is invalid or has expired' });
      }
      req.technician = technician;
      const attempt = await requireOwnAttemptByIdentification(req, res);
      if (!attempt) return undefined;
      employeeId = technician.id;
      attemptId = attempt.id;
    }

    return res.json(await marking.readResultFor(
      { accountId: null, employeeId, isAdmin: false, holdsMarkCodes: false },
      attemptId
    ));
  } catch (error) {
    return refuse(error, res, next);
  }
});

module.exports = router;
