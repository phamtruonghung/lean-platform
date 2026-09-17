/*
 * Non-conformances over the shared floor device's own door (issue #207,
 * ADR-0016). Mounted by index.js under `/api/quality`, beside
 * nonconformance-routes.js, and reached only with the device credential
 * People issued it (#201) plus an individual identification.
 *
 * ## Why these addresses live under `/api/quality`
 *
 * `/api/quality/floor/products`, `/api/quality/floor/defect-codes` and
 * `/api/quality/floor/nonconformances` are new addresses this Module chooses
 * for itself, and the choice is the opposite of the one #201 recorded — on
 * purpose. The device, its PINs and its identification exchange stayed at the
 * `/api/maintenance/floor/...` paths they have always had, because a deployed
 * tablet is pointed at those URLs and the move into People's records must not
 * be visible to a caller (people/floor-routes.js's header is where that
 * argument is written down). Nothing in the field is pointed at a Quality
 * address: this ticket creates the first one, so there is no compatibility to
 * keep and no reason to file a Quality record's door under a prefix that would
 * claim Maintenance owns it. A caller can tell which Module answered, which is
 * the honest shape when the address is new; had these paths existed before the
 * move, they would have stayed where they were.
 *
 * ## What a device may do here, and what it may not
 *
 * Three things, and nothing else:
 *
 *   - Read the two catalogues it must choose from. A Non-conformance names a
 *     Product and a Defect code, and ADR-0023's rule is that a value with a
 *     known set is chosen rather than typed — which a device standing at a
 *     machine cannot do without reading the sets it is choosing between. Both
 *     are platform-wide reference data (ADR-0005), not Org-Unit scoped, so a
 *     device reading them learns nothing about the plant's shape that any
 *     approved Account could not read from `/api/quality/products` anyway.
 *     They are deliberately separate addresses rather than a device door on
 *     the Account-facing catalogue routes: the Account routes' access rule is
 *     "any approved Account", and widening it to a second kind of caller is a
 *     change to a contract this ticket has no business making.
 *   - Record a Non-conformance, and only for the Org Unit the device is
 *     registered at and everything beneath it. A device reports for its own
 *     part of the plant; it is not a way to file a record against somewhere
 *     else, and `people.deviceReachesOrgUnit` (People's own tree, reached
 *     through its entry point like every other cross-Module question) is what
 *     answers that.
 *   - Nothing that needs Quality authority. A Concession, a lowered severity,
 *     a reopen and a cancel are never reachable from this file: they are not
 *     mounted here at all, and they sit behind `people.authenticate` on their
 *     own addresses, so a request carrying only a device credential is refused
 *     there before anything is looked at. Recording is work rather than a
 *     decision — the same line nonconformance-routes.js draws — so it is the
 *     one write the floor door has, which is why this file has exactly one.
 *
 * ## The door, and the ordering behind it
 *
 * `x-floor-device` selects this door and `x-technician-identification` says
 * which Employee is standing at the machine. A missing, unknown or inactive
 * device is a 401 and so is a missing, invalid, expired or other-device
 * identification — the same four refusals, in the same wording, that
 * maintenance/work-order-routes.js gives its floor writes, copied rather than
 * respelled so a technician cannot learn a different sentence for the same
 * mistake depending on which machine they are at. A device alone is never
 * enough to write anything: the identification is what makes a record
 * attributable to a person, and ADR-0016's whole point is that the device
 * itself is not one.
 *
 * Inside the handler the order is existence before scope, the same ordering
 * every write route in this Platform follows (AGENTS.md §6): the Org Unit is
 * parsed (400) and resolved (404) first, then the device's reach of it is
 * asked (403 with People's own `OUTSIDE_GRANTED_ORG_UNITS`), and only then is
 * `recordNonconformance` called — so a bad Org Unit id is a 404 naming it
 * rather than a scope refusal that would read as a permission problem. The
 * field, severity and quantity rules are not re-stated here at all: they are
 * the service's, so a device gets exactly the rules an Account gets, refusals
 * and sentences included.
 */

const express = require('express');
const people = require('../people');
const products = require('./products');
const defectCodes = require('./defect-codes');
const nonconformances = require('./nonconformances');
const { notFound, parseId, handleError } = require('./errors');

const router = express.Router();

// The device's own credential, presented on every floor request — deliberately
// a separate header from an Account's bearer token, so the two doors cannot be
// confused. An inactive device is refused the same way an unknown one is, and
// the wording is maintenance's floor routes' word for word.
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

// The individual identification, required on every floor WRITE and on none of
// the floor reads: reading what the plant makes and what can go wrong with it
// is not an act anybody is held to, and the catalogues are shared reference
// data. The token resolves only for the device it was issued on and only
// while it is inside its window (People's `findValidIdentification`), so a
// token carried to another machine or presented after a shift change is the
// same 401 as a made-up one.
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

// The Product catalogue, active rows only: a retired Product cannot be
// recorded against at all (`recordNonconformance` answers 409 for one), so
// offering it as a choice would be a form asking a question whose answer is
// already no. Same for the Defect codes below.
router.get('/floor/products', requireFloorDevice, async (req, res, next) => {
  try {
    res.json({ products: await products.listProducts({ includeInactive: false }) });
  } catch (error) {
    handleError(error, res, next);
  }
});

router.get('/floor/defect-codes', requireFloorDevice, async (req, res, next) => {
  try {
    res.json({ defectCodes: await defectCodes.listDefectCodes({ includeInactive: false }) });
  } catch (error) {
    handleError(error, res, next);
  }
});

// Recording a Non-conformance at a shared floor device (issue #207).
//
// `orgUnitId` is required and explicit rather than defaulted to the device's
// own Org Unit, even though that is what the client sends: the account door
// takes the same field with the same 400, and a default would mean two doors
// disagreeing about what a missing field means. The device's own Org Unit is
// where its reach starts, never a bound on what may be named — anything at or
// beneath it is fair game, which is what "a device only reports for its own
// Org Unit and beneath it" means.
router.post(
  '/floor/nonconformances',
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

      const nonconformance = await nonconformances.recordNonconformance(
        { ...body, orgUnitId: orgUnit.id },
        // The floor door's actor: the identified Employee IS who detected it,
        // and there is no Account on this path at all (ADR-0016 — most of a
        // plant cannot sign in), so `recorded_by_account_id` stays null.
        { employeeId: req.technician.id }
      );

      res.status(201).json({ nonconformance });
    } catch (error) {
      handleError(error, res, next);
    }
  }
);

module.exports = router;
