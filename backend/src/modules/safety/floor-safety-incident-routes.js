/*
 * Safety incidents over the shared floor device's own door (issue #227,
 * ADR-0016, ADR-0036). Mounted by index.js under `/api/safety`, beside
 * safety-incident-routes.js, and reached only with the device credential
 * People issued it plus an individual identification.
 *
 * ## Why this address lives under `/api/safety`
 *
 * `/api/safety/floor/incidents` is a new address this Module chooses for
 * itself, the same reasoning `quality/floor-routes.js`'s own header gives for
 * `/api/quality/floor/nonconformances`: nothing in the field is pointed at a
 * Safety address before this ticket, so there is no compatibility to keep and
 * no reason to file this door under a prefix that would claim another Module
 * owns it. A caller can tell which Module answered, which is the honest shape
 * when the address is new.
 *
 * ## What a device may do here, and what it may not
 *
 * One thing, and nothing else: record a Safety incident, and only for the Org
 * Unit the device is registered at and everything beneath it. There is no
 * catalogue read here the way Quality's floor door has one — incident type
 * and severity level are fixed enums, baked into both client and server
 * (`INCIDENT_TYPES`, `SEVERITY_LEVELS` in `safety-incidents.js`), not
 * admin-maintained reference data a device would need to fetch before it can
 * render a form. A device reports for its own part of the plant;
 * `people.deviceReachesOrgUnit` (People's own tree, reached through its entry
 * point like every other cross-Module question) is what answers that.
 *
 * No injury classification is accepted from this door — issue #223's own
 * binding comment on the floor form's fields. As of issue #224 that is
 * **enforced rather than assumed**: `employeeId`, `injuryTypeId` and
 * `bodyPartId` are stripped from the body below before it reaches
 * `recordSafetyIncident`, which accepts all three from any caller. Classifying
 * an injury needs Safety authority reaching the Org Unit (ADR-0039), a floor
 * identification is not an Account and can hold no Grant at all, so there is
 * no standing here that could ever satisfy that gate — a crafted request to
 * this address must not be able to do what the Account door refuses.
 *
 * For the same reason the answer this door sends is passed through
 * `withoutInjuryDetails` unconditionally. There is nothing to withhold today —
 * the three fields are always null on a record written here — so this costs
 * nothing and is not a judgement about the technician standing at the device;
 * it is the door staying shut by default, so that widening the floor form one
 * day cannot quietly open it.
 *
 * And there is no anonymous option, ever — ADR-0036, unconditionally. The
 * floor door identifies an Employee before it accepts a write at all: the
 * identification itself, not the write, is what makes this different from the
 * Account door.
 *
 * ## The door, and the ordering behind it
 *
 * `x-floor-device` selects this door and `x-technician-identification` says
 * which Employee is standing at the machine — the same two headers, the same
 * four 401 refusals in the same wording, that `quality/floor-routes.js` and
 * maintenance's floor writes already give. A device alone is never enough to
 * write anything: the identification is what makes a record attributable to a
 * person, and it is who this file records as the reporter — never an Account,
 * because there is no Account on this path at all (ADR-0016 — most of a plant
 * cannot sign in).
 *
 * Inside the handler the order is existence before scope, the same ordering
 * every write route in this Platform follows (AGENTS.md §6): the Org Unit is
 * parsed (400) and resolved (404) first, then the device's reach of it is
 * asked (403 with People's own `OUTSIDE_GRANTED_ORG_UNITS`), and only then is
 * `recordSafetyIncident` called — so a bad Org Unit id is a 404 naming it
 * rather than a scope refusal that would read as a permission problem. The
 * field, ladder-consistency and numbering rules are not re-stated here at all:
 * they are the service's, the same one the Account door calls, so a device
 * gets exactly the rules an Account gets, refusals and sentences included.
 */

const express = require('express');
const people = require('../people');
const safetyIncidents = require('./safety-incidents');
const { notFound, parseId, handleError } = require('./errors');

const router = express.Router();

// The device's own credential, presented on every floor request — copied word
// for word from quality/floor-routes.js's own requireFloorDevice, so a
// technician cannot learn a different sentence for the same mistake depending
// on which Module's floor door they are at.
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
// word for word from quality/floor-routes.js's own
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

// Recording a Safety incident at a shared floor device (issue #227).
//
// `orgUnitId` is required and explicit rather than defaulted to the device's
// own Org Unit, even though that is what the client sends: the Account door
// takes the same field with the same 400, and a default would mean two doors
// disagreeing about what a missing field means. The device's own Org Unit is
// where its reach starts, never a bound on what may be named — anything at or
// beneath it is fair game, which is what "a device only reports for its own
// Org Unit and beneath it" means.
router.post(
  '/floor/incidents',
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

      // The injury classification, removed rather than refused. A floor form
      // never collects these, so a body carrying one is not a technician's
      // mistake to explain — and a 400 would be this door telling whoever
      // crafted it which fields exist. See this file's header.
      const { employeeId, injuryTypeId, bodyPartId, ...reportable } = body;

      const incident = await safetyIncidents.recordSafetyIncident(
        { ...reportable, orgUnitId: orgUnit.id },
        // The floor door's actor: the identified Employee IS the reporter, and
        // there is no Account on this path at all (ADR-0016), so
        // `recorded_by_account_id` stays null and `reported_by` is set instead
        // — the opposite of the Account door.
        { employeeId: req.technician.id }
      );

      res.status(201).json({ incident: safetyIncidents.withoutInjuryDetails(incident) });
    } catch (error) {
      handleError(error, res, next);
    }
  }
);

module.exports = router;
