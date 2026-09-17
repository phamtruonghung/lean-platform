/*
 * The shared floor device's own HTTP surface (issue #77, ADR-0016), owned by
 * the people Module since issue #201: an administrator registering a device,
 * setting an Employee's floor PIN and the exchange that turns a number and a
 * PIN into a short-lived identification are all about who an Employee is, not
 * about maintenance.
 *
 * Three routes, and the split between them is the decision:
 *
 *   - POST /floor-devices — an administrator, or any Account holding a write
 *     Grant reaching the Org Unit, registers one shared device against that
 *     Org Unit and receives its credential exactly once. Reading the
 *     credential back is impossible by construction; only its hash is stored.
 *     Registering real hardware is an operational task out of this ticket's
 *     scope, but a device has to come into existence somehow, and this is the
 *     one door that does it.
 *
 *   - PUT /floor-technician-credentials/:employeeId — an administrator sets
 *     the PIN an Employee presents at a machine. It is keyed to the Employee,
 *     never to an Account: most of a plant cannot sign in (CONTEXT.md), and
 *     this credential must not require that they can. The PIN is never
 *     returned.
 *
 *   - POST /floor/identify — the device presents its own credential and an
 *     Employee presents their number and PIN; back comes a short-lived
 *     identification token naming the Employee. This is the ONLY place the
 *     device's credential is used for anything but reading.
 *
 * ## The address is frozen under /api/maintenance
 *
 * These three paths stay where a floor device has always called them. The
 * records are People's now, but the URL is not: a deployed tablet or terminal
 * is pointed at `/api/maintenance/floor-devices`,
 * `/api/maintenance/floor-technician-credentials/:employeeId` and
 * `/api/maintenance/floor/identify`, the frontend is not part of this move
 * (issue #201 keeps its HTTP surface as it was), and nothing a caller can
 * observe distinguishes which Module answered. `src/index.js` composes this
 * router at that prefix for exactly that reason — the prefix is an address
 * kept, not a claim that Maintenance owns the route. Moving these under
 * `/api/people` would break every device in the field to buy a tidier URL.
 *
 * ## What is deliberately NOT here
 *
 * The floor WRITE surface: a floor write is a POST to the existing
 * `/work-orders/:id/start` and `/complete` routes (issue #63), which is
 * Maintenance's own record. `maintenance/work-order-routes.js` selects the
 * device door and asks this Module's entry point who the device and the
 * identified Employee are. The floor READ — `GET /floor/work-orders`, which
 * lists Work orders rather than saying anything about a device — stays with
 * Maintenance too, in `maintenance/floor-routes.js`, and resolves the device
 * through the entry point the same way.
 *
 * `authenticate`/`requireActive`/`findOrgUnit`/`findEmployee`/`canAct` are
 * this Module's own files, reached directly as every other People route
 * reaches them (AGENTS.md §6) — this file is inside People, so there is no
 * entry point in between. The admin gate is a role check on the resolved
 * Account, the same shape People's own administrator routes use. Existence is
 * resolved before anything is written.
 */

const express = require('express');
const floorDevices = require('./floor-devices');
const { authenticate, requireActive } = require('./middleware');
const { canAct } = require('./authorization');
const { findOrgUnit } = require('./plant');
const { findEmployee } = require('./directory');
const { httpError, notFound, parseId, handleError, OUTSIDE_GRANTED_ORG_UNITS } = require('./errors');

const router = express.Router();

// Administrator-only, expressed at this Module's own route. Runs after
// authenticate + requireActive, so `req.account` is a real, admitted Account.
// The wording matches the other administrator-only routes in this backend
// (maintenance/job-plan-routes.js, maintenance/inventory-routes.js). Only the
// technician credential is gated this way — it is a People-shaped write about
// one Employee, not an Org-Unit-scoped one. Registering a device is scoped by
// its Org Unit Grant (see registerDevice below), not by role.
function requireAdmin(req, res, next) {
  if (req.account.role !== 'admin') {
    return res.status(403).json({ message: 'This action requires the administrator role.' });
  }
  return next();
}

// The device's own credential, presented on every floor request. Deliberately
// a separate header from the Account's bearer token so the two doors cannot be
// confused: `work-order-routes.js` decides which door a write came through by
// the presence of this header alone. An inactive device is refused the same
// way an unknown one is.
async function requireFloorDevice(req, res, next) {
  try {
    const device = await floorDevices.findDeviceByCredential(req.headers['x-floor-device']);
    if (!device || !device.isActive) {
      return res.status(401).json({ message: 'Invalid or inactive floor device' });
    }
    req.floorDevice = device;
    return next();
  } catch (error) {
    return handleError(error, res, next);
  }
}

async function registerDevice(req, res, next) {
  try {
    const orgUnitId = parseId(req.body?.orgUnitId);
    if (orgUnitId === null) {
      return res.status(400).json({ message: 'orgUnitId must be a valid Org Unit id' });
    }
    const name = req.body?.name;
    if (typeof name !== 'string' || name.trim() === '') {
      return res.status(400).json({ message: 'name is required' });
    }

    // Existence before scope, the same ordering every write route in this
    // Platform follows (AGENTS.md §6): findOrgUnit is total, so an unknown id is
    // a clean 404 naming the Org Unit, and only then is the write Grant
    // question asked. `write: true` is passed explicitly and must stay that
    // way — canAct's `write` defaults to FALSE, so dropping it would silently
    // authorise a device registration on any read Grant with no error
    // anywhere to notice.
    const orgUnit = await findOrgUnit(orgUnitId);
    if (!orgUnit) throw notFound('Org Unit');
    const allowed = await canAct({ account: req.account, orgUnitId: orgUnit.id, write: true });
    if (!allowed) throw httpError(403, OUTSIDE_GRANTED_ORG_UNITS);

    const { device, credential } = await floorDevices.createFloorDevice(
      { orgUnitId, name },
      req.account.id
    );
    res.status(201).json({ device, credential });
  } catch (error) {
    handleError(error, res, next);
  }
}

async function setTechnicianCredential(req, res, next) {
  try {
    const employeeId = parseId(req.params.employeeId);
    if (employeeId === null) throw notFound('Employee');

    const employee = await findEmployee(employeeId);
    if (!employee) throw notFound('Employee');
    if (!employee.isActive) {
      throw httpError(409, 'this Employee has departed and cannot be given a floor credential');
    }

    const credential = await floorDevices.setEmployeePin(
      employee.id,
      req.body?.pin,
      req.account.id
    );
    // The secret is never echoed: the response says who the credential belongs
    // to and nothing about what it is.
    res.json({ employeeId: credential.employeeId, isActive: credential.isActive });
  } catch (error) {
    handleError(error, res, next);
  }
}

// The identification exchange. A wrong Employee number and a wrong PIN answer
// identically, and neither says whether the Employee exists — this endpoint is
// not a way to enumerate a plant's workforce.
async function identify(req, res, next) {
  try {
    const credential = await floorDevices.findCredentialForEmployeeNo(req.body?.employeeNo);
    const pin = typeof req.body?.pin === 'string' ? req.body.pin : '';
    if (!credential || !(await floorDevices.verifyPin(pin, credential.pinHash))) {
      return res.status(401).json({ message: 'That Employee number and PIN were not recognised' });
    }

    const { token, expiresAt } = await floorDevices.createIdentification({
      deviceId: req.floorDevice.id,
      employeeId: credential.employee.id
    });
    res.json({ identification: token, expiresAt, employee: credential.employee });
  } catch (error) {
    handleError(error, res, next);
  }
}

router.post(
  '/floor-devices',
  authenticate,
  requireActive,
  registerDevice
);

router.put(
  '/floor-technician-credentials/:employeeId',
  authenticate,
  requireActive,
  requireAdmin,
  setTechnicianCredential
);

router.post('/floor/identify', requireFloorDevice, identify);

module.exports = router;
