/*
 * Maintenance's own floor-device read (issue #77, ADR-0016): the shared device
 * presents the credential People issued it and reads the open work at its own
 * Org Unit and everything beneath it. Nothing else, ever.
 *
 * This is what is left on this side of the seam after issue #201 moved the
 * device itself into the people Module. Registering a device, setting an
 * Employee's floor PIN and exchanging them for an identification are People's
 * routes now (`modules/people/floor-routes.js`), as is the credential and the
 * identification store (`modules/people/floor-devices.js`). What stays here is
 * the part that is about Work orders rather than about a device: which of
 * Maintenance's rows a device may see, and the answer is this Module's own
 * list. The device is resolved through `modules/people`'s entry point
 * (ADR-0006) — `findDeviceByCredential` to prove the credential is a live
 * device at all, then `findDeviceContext` for the Site and Org Unit path the
 * read is bounded by, which is People's own tree and People's own question.
 *
 * The address is frozen too, and for the same reason: a deployed device reads
 * `/api/maintenance/floor/work-orders`, so the path stays where it has always
 * been even though half of what answers it now lives in another Module.
 * `maintenance/index.js` mounts this router under `/api/maintenance`; the
 * three People-owned floor routes are mounted at that same prefix by
 * `src/index.js`. Neither move is visible to a caller.
 *
 * The write surface itself is NOT here either. A floor write is a POST to the
 * existing `/work-orders/:id/start` and `/complete` routes (issue #63),
 * carrying the device credential and the identification; `work-order-routes.js`
 * owns the combined actor middleware and the scope check for both doors.
 */

const express = require('express');
const people = require('../people');
const workOrders = require('./work-orders');
const { handleError } = require('./errors');

const router = express.Router();

// The device's own credential, presented on every floor request. Deliberately
// a separate header from the Account's bearer token so the two doors cannot be
// confused: `work-order-routes.js` decides which door a write came through by
// the presence of this header alone. An inactive device is refused the same
// way an unknown one is. The credential store is People's (issue #201), so
// this is an entry-point question, not a local read.
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

async function listFloorWorkOrders(req, res, next) {
  try {
    const context = await people.findDeviceContext(req.floorDevice.id);
    if (!context) return res.status(401).json({ message: 'Invalid or inactive floor device' });

    // The device's own Org Unit path is what bounds the read: the Org Unit it
    // is registered against and everything beneath it, via the same ltree
    // containment `listWorkOrdersAtSite` already uses. The device cannot ask
    // for a different one — there is no such parameter.
    const list = await workOrders.listWorkOrdersAtSite(context.siteId, {
      orgUnitPath: context.orgUnitPath
    });
    res.json({
      floor: {
        orgUnitId: context.orgUnitId,
        orgUnitName: context.orgUnitName,
        siteId: context.siteId
      },
      workOrders: list
    });
  } catch (error) {
    handleError(error, res, next);
  }
}

router.get('/floor/work-orders', requireFloorDevice, listFloorWorkOrders);

module.exports = router;
