/*
 * Safety observations over the shared floor device's own door (issue #230,
 * ADR-0016). Mounted by index.js under `/api/safety`, beside
 * safety-observation-routes.js, and reached only with the device credential
 * People issued it plus an individual identification — the same shape
 * floor-safety-incident-routes.js already gives an incident's own floor door.
 *
 * ## What a device may do here, and what it may not
 *
 * One thing, and nothing else: record a Safety observation, and only for the
 * Org Unit the device is registered at and everything beneath it. There is no
 * catalogue read here — observation type, category and severity potential are
 * fixed enums, baked into both client and server (`OBSERVATION_TYPES`,
 * `CATEGORIES`, `SEVERITY_POTENTIALS` in `safety-observations.js`), not
 * admin-maintained reference data a device would need to fetch before it can
 * render a form. A device reports for its own part of the plant;
 * `people.deviceReachesOrgUnit` (People's own tree, reached through its entry
 * point like every other cross-Module question) is what answers that.
 *
 * ## The door, and the ordering behind it
 *
 * `x-floor-device` selects this door and `x-technician-identification` says
 * which Employee is standing at the machine — the same two headers, the same
 * two 401 refusals in the same wording, `floor-safety-incident-routes.js`
 * already gives. A device alone is never enough to write anything: the
 * identification is what makes a record attributable to a person, and it is
 * who this file records as the observer — never an Account, because there is
 * no Account on this path at all (ADR-0016 — most of a plant cannot sign in).
 *
 * Inside the handler the order is existence before scope, the same ordering
 * every write route in this Platform follows (AGENTS.md §6): the Org Unit is
 * parsed (400) and resolved (404) first, then the device's reach of it is
 * asked (403 with People's own `OUTSIDE_GRANTED_ORG_UNITS`), and only then is
 * `recordSafetyObservation` called — so a bad Org Unit id is a 404 naming it
 * rather than a scope refusal that would read as a permission problem. The
 * field and enum-membership rules are not re-stated here at all: they are the
 * service's, the same one the Account door calls, so a device gets exactly
 * the rules an Account gets, refusals and sentences included.
 */

const express = require('express');
const people = require('../people');
const safetyObservations = require('./safety-observations');
const { notFound, parseId, handleError } = require('./errors');

const router = express.Router();

// The device's own credential, presented on every floor request — copied word
// for word from floor-safety-incident-routes.js's own requireFloorDevice, so
// a technician cannot learn a different sentence for the same mistake
// depending on which door they are at.
async function requireFloorDevice(req, res, next) {
  try {
    const device = await people.findDeviceByCredential(req.headers['x-floor-device']);
    if (!device || !device.isActive) {
      return res.status(401).json({ message: 'Invalid or inactive floor device' });
    }
    req.floorDevice = device;
    return next();
  } catch (error) {
    return handleError(error, res, next);
  }
}

// The individual identification, required on this door's one write — copied
// word for word from floor-safety-incident-routes.js's own
// requireTechnicianIdentification.
async function requireTechnicianIdentification(req, res, next) {
  try {
    const token = req.headers['x-technician-identification'];
    if (typeof token !== 'string' || token === '') {
      return res
        .status(401)
        .json({ message: 'An individual identification is required to write here' });
    }
    const technician = await people.findValidIdentification(token, req.floorDevice.id);
    if (!technician) {
      return res.status(401).json({ message: 'This identification is invalid or has expired' });
    }
    req.technician = technician;
    return next();
  } catch (error) {
    return handleError(error, res, next);
  }
}

// Recording a Safety observation at a shared floor device (issue #230).
//
// `orgUnitId` is required and explicit rather than defaulted to the device's
// own Org Unit: the Account door takes the same field with the same 400, and
// a default would mean two doors disagreeing about what a missing field
// means. The device's own Org Unit is where its reach starts, never a bound
// on what may be named — anything at or beneath it is fair game.
router.post(
  '/floor/observations',
  requireFloorDevice,
  requireTechnicianIdentification,
  async (req, res, next) => {
    try {
      const body = req.body ?? {};

      const orgUnitId = parseId(body.orgUnitId);
      if (orgUnitId === null) {
        return res.status(400).json({ message: 'orgUnitId must be a valid Org Unit id' });
      }
      const orgUnit = await people.findOrgUnit(orgUnitId);
      if (!orgUnit) throw notFound('Org Unit');

      const reaches = await people.deviceReachesOrgUnit(req.floorDevice.orgUnitId, orgUnit.id);
      if (!reaches) {
        return res.status(403).json({ message: people.OUTSIDE_GRANTED_ORG_UNITS });
      }

      const observation = await safetyObservations.recordSafetyObservation(
        { ...body, orgUnitId: orgUnit.id },
        // The floor door's actor: the identified Employee IS the observer,
        // and there is no Account on this path at all (ADR-0016), so
        // `recorded_by_account_id` stays null and `observer_employee_id` is
        // set instead — the opposite of the Account door.
        { employeeId: req.technician.id }
      );

      res.status(201).json({ observation });
    } catch (error) {
      handleError(error, res, next);
    }
  }
);

module.exports = router;
