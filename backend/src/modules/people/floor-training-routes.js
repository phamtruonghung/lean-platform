/*
 * A Trainee's answer at the shared floor device (issue #293, ADR-0016,
 * ADR-0043): the second door onto the same write `training-routes.js` gives an
 * Account. Most of a plant holds no Account, so an Employee identifies at the
 * device with their number and PIN and answers the trainings waiting on them.
 *
 * Three routes, on the frozen `/api/maintenance` prefix the deployed devices are
 * pointed at (#201) - composed into `floorRouter` by index.js beside
 * floor-routes.js, and owned by People because a Training record is People's:
 *
 *   - GET  /floor/training/to-confirm - the identified Employee's own
 *     unanswered rows on sent records, bounded to the device's Org Unit and
 *     everything beneath it (the device's path, as the Maintenance floor read
 *     bounds Work orders). A draft is never listed.
 *   - POST /floor/training/trainees/:traineeId/answer - `confirmed` or
 *     `declined`, written as the same columns the Account door writes, with
 *     `answered_by_employee_id` filled and `answered_by_account_id` null; the
 *     record's own read tells the two doors apart by `answeredVia` alone. The
 *     optional `signature` (#319) is the Account door's own: `{ use: "stored" }`
 *     or `{ image }`, parsed and refused alike (a decline carrying one is a 400)
 *     before anything is read. `stored` is the identified Employee's own current
 *     kept Signature; `image` is a one-off row with no Account. The device can
 *     never create or supersede a kept Signature.
 *   - GET  /floor/signature - the identified Employee's current kept Signature
 *     as `image/png`, 404 when none is kept: the only way a device, which has no
 *     Account and so no `/me/signature`, can show it before it is applied.
 *
 * The door: `x-floor-device` (401 when unknown or inactive) and
 * `x-technician-identification` (401 when missing, expired or issued to another
 * device), in the wording the Safety floor routes use. Nothing is re-read here:
 * the device, the identification and the reach come from this Module's own
 * floor-devices.js.
 *
 * The answer's order: the answer value (400), the Trainee row (404) or its
 * record still a draft (404 - a draft is not yet a fact, as at the Account
 * door), the record's Org Unit outside the device's reach (403 with
 * OUTSIDE_GRANTED_ORG_UNITS), the Trainee not the identified Employee (403 -
 * an answer is a person's own signature), then the write. There is no Account
 * on this path, so the audit carries no Account, as Safety's floor writes do.
 */

const express = require('express');
const floorDevices = require('./floor-devices');
const training = require('./training');
const signatures = require('./signatures');
const { requireFloorDevice } = require('./floor-device-middleware');
const { notFound, httpError, handleError, OUTSIDE_GRANTED_ORG_UNITS } = require('./errors');

const router = express.Router();

// Same wording as the Safety floor routes' requireTechnicianIdentification.
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

router.get(
  '/floor/training/to-confirm',
  requireFloorDevice,
  requireTechnicianIdentification,
  async (req, res, next) => {
    try {
      const context = await floorDevices.findDeviceContext(req.floorDevice.id);
      if (!context) return res.status(401).json({ message: 'Invalid or inactive floor device' });

      const trainingToConfirm = await training.listTrainingToConfirm(req.technician.id, {
        orgUnitPath: context.orgUnitPath
      });
      return res.json({ trainingToConfirm });
    } catch (error) {
      return handleError(error, res, next);
    }
  }
);

// The identified Employee's own current Signature, so the device can show it
// before it is applied and render no stored choice when none is kept (404).
// Read-only by design: the device has no route that sets, replaces or removes
// a kept Signature (ADR-0052) - that is the Employee's own Account's act.
router.get(
  '/floor/signature',
  requireFloorDevice,
  requireTechnicianIdentification,
  async (req, res, next) => {
    try {
      const image = await signatures.getCurrentSignature(req.technician.id);
      res.set('Cache-Control', 'private, no-cache');
      return res.type('image/png').send(image);
    } catch (error) {
      return handleError(error, res, next);
    }
  }
);

router.post(
  '/floor/training/trainees/:traineeId/answer',
  requireFloorDevice,
  requireTechnicianIdentification,
  async (req, res, next) => {
    try {
      const answer = training.requireAnswer(req.body?.answer);
      const applied = signatures.parseApplied(req.body?.signature);
      if (applied !== null && answer === 'declined') {
        throw httpError(400, 'a declined answer carries no Signature');
      }
      const trainee = await training.findTraineeForAnswer(req.params.traineeId);
      if (!trainee || trainee.recordStatus !== 'sent') throw notFound('Trainee');

      const reaches = await floorDevices.deviceReachesOrgUnit(
        req.floorDevice.orgUnitId,
        trainee.orgUnitId
      );
      if (!reaches) {
        return res.status(403).json({ message: OUTSIDE_GRANTED_ORG_UNITS });
      }
      if (String(trainee.employeeId) !== String(req.technician.id)) {
        return res.status(403).json({ message: 'Only the Trainee can answer for themselves' });
      }

      const updated = await training.answerTraineeAtFloor(req.technician.id, trainee.id, answer, applied);
      return res.json({ trainingRecord: updated });
    } catch (error) {
      return handleError(error, res, next);
    }
  }
);

module.exports = router;
