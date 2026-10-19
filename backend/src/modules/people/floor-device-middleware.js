/*
 * The one copy of the floor device door for People's floor routes
 * (floor-routes.js and floor-training-routes.js).
 *
 * The device's own credential, presented on every floor request. Deliberately
 * a separate header from the Account's bearer token so the two doors cannot be
 * confused: `work-order-routes.js` decides which door a write came through by
 * the presence of this header alone. An inactive device is refused the same
 * way an unknown one is.
 */

const floorDevices = require('./floor-devices');
const { handleError } = require('./errors');

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

module.exports = { requireFloorDevice };
