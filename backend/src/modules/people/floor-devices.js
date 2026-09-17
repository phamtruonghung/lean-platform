/*
 * The shared floor device and the individual identification a technician
 * presents on it (issue #77, ADR-0016), owned by the people Module since
 * issue #201: registering a device against an Org Unit, setting an Employee's
 * floor PIN and issuing the short-lived identification token are all about who
 * an Employee is, not about maintenance. `floor-routes.js` owns the HTTP
 * surface and the request-shape validation, the same split
 * `plant.js`/`plant-routes.js` follow (AGENTS.md §6).
 *
 * This file is People's own service and requires no other Module — nothing
 * under `modules/` does (ADR-0006). `floor_devices`,
 * `employee_floor_credentials` and `technician_identifications` are records
 * this Module owns; it joins `employees` for the Employee a credential belongs
 * to, the ordinary cross-table read within one Module.
 *
 * ## Secrets
 *
 * Two kinds of secret cross this surface, and each is stored only as a hash:
 *
 *   - The device credential is high-entropy (24 random bytes, base64url), so
 *     its SHA-256 is enough and, because the digest is deterministic, a device
 *     is looked up by it directly.
 *   - A technician's PIN is low-entropy, so it is hashed with a per-credential
 *     random salt and scrypt, and verified against the Employee the caller
 *     named. Nothing here ever returns or logs either secret.
 *
 * The identification token is likewise stored only as its SHA-256. It is the
 * one secret that IS returned to a caller — once, by the identify endpoint —
 * because that is what the caller then presents on the write; it is ephemeral
 * by construction (short expiry, one device, one Employee).
 */

const crypto = require('node:crypto');
const { promisify } = require('node:util');
const { getPool, withActor } = require('../../platform/db');
const { httpError, parseId } = require('./errors');

const scrypt = promisify(crypto.scrypt);
const SCRYPT_KEY_LENGTH = 32;
const PIN_PATTERN = /^[0-9]{4,8}$/;

// How long an identification is good for. Deliberately short: ADR-0016's own
// requirement is that "who was at the machine" and "who the system attributed
// the action to" cannot drift across a shift change. Two minutes is long
// enough for the client to identify once and immediately start (and, if the
// technician stays at the machine, complete), and short enough that a walked
// -away device stops attributing to the last person quickly.
const IDENTIFICATION_TTL_SECONDS = 120;

function sha256(value) {
  return crypto.createHash('sha256').update(value).digest('hex');
}

async function hashPin(pin) {
  const salt = crypto.randomBytes(16).toString('hex');
  const derived = await scrypt(pin, salt, SCRYPT_KEY_LENGTH);
  return `scrypt$${salt}$${derived.toString('hex')}`;
}

async function verifyPin(pin, stored) {
  const [scheme, salt, expectedHex] = String(stored).split('$');
  if (scheme !== 'scrypt' || !salt || !expectedHex) return false;
  const derived = await scrypt(pin, salt, SCRYPT_KEY_LENGTH);
  const expected = Buffer.from(expectedHex, 'hex');
  return derived.length === expected.length && crypto.timingSafeEqual(derived, expected);
}

// A malformed employeeNo is not an error the caller needs told apart from a
// good one that simply matched nothing: both answer "not recognised", so the
// caller cannot use this endpoint to enumerate Employees.
function normaliseEmployeeNo(employeeNo) {
  if (typeof employeeNo !== 'string') return null;
  const trimmed = employeeNo.trim();
  return trimmed === '' ? null : trimmed;
}

// Registers a device against an Org Unit and returns the presentable
// credential exactly once. The caller (the route) has already proven the Org
// Unit exists and that the caller may register a device — this function only
// writes, as `createWorkOrder` does.
async function createFloorDevice({ orgUnitId, name }, accountId) {
  const credential = crypto.randomBytes(24).toString('base64url');
  const device = await withActor(accountId, async (client) => {
    const { rows: [row] } = await client.query(
      `INSERT INTO floor_devices (org_unit_id, name, credential_hash)
       VALUES ($1, $2, $3)
       RETURNING id, org_unit_id, name, is_active`,
      [orgUnitId, name.trim(), sha256(credential)]
    );
    return toFloorDevice(row);
  });
  return { device, credential };
}

function toFloorDevice(row) {
  return {
    id: row.id,
    orgUnitId: row.org_unit_id,
    name: row.name,
    isActive: row.is_active
  };
}

// Resolves a presented device credential to its device, or null. The device
// is returned even when inactive so the route can tell "not a device" from
// "a device switched off" if it ever needs to; today it refuses both.
//
// Reached from another Module through this Module's entry point (issue #201):
// it is the question "is this a device, and is it switched on" that
// maintenance's floor writes and its floor read both ask before anything is
// written, and it answers with a value rather than a throw (ADR-0006).
async function findDeviceByCredential(credential) {
  if (typeof credential !== 'string' || credential === '') return null;
  const { rows } = await getPool().query(
    `SELECT id, org_unit_id, name, is_active
       FROM floor_devices
      WHERE credential_hash = $1`,
    [sha256(credential)]
  );
  return rows[0] ? toFloorDevice(rows[0]) : null;
}

// The device plus the Org Unit it is registered against — the name and Site a
// floor read carries back, and the Org Unit path that decides what it may
// read. Resolved once per read rather than trusting the id alone.
async function findDeviceContext(deviceId) {
  if (parseId(deviceId) === null) return null;
  const { rows } = await getPool().query(
    `SELECT d.id, d.org_unit_id, d.name, d.is_active,
            ou.name AS org_unit_name, ou.site_id, ou.path AS org_unit_path
       FROM floor_devices d
       JOIN org_units ou ON ou.id = d.org_unit_id
      WHERE d.id = $1`,
    [deviceId]
  );
  const row = rows[0];
  if (!row) return null;
  return {
    ...toFloorDevice(row),
    orgUnitName: row.org_unit_name,
    siteId: row.site_id,
    orgUnitPath: row.org_unit_path
  };
}

// Sets (or replaces) one Employee's PIN. Upsert, because an Employee has at
// most one floor credential (`employee_id` is UNIQUE) and re-provisioning is a
// replacement, not a second credential.
async function setEmployeePin(employeeId, pin, accountId) {
  if (!PIN_PATTERN.test(String(pin ?? ''))) {
    throw httpError(400, 'pin must be 4 to 8 digits');
  }
  const pinHash = await hashPin(String(pin));
  return withActor(accountId, async (client) => {
    const { rows: [row] } = await client.query(
      `INSERT INTO employee_floor_credentials (employee_id, pin_hash)
       VALUES ($1, $2)
       ON CONFLICT (employee_id)
       DO UPDATE SET pin_hash = EXCLUDED.pin_hash, is_active = TRUE
       RETURNING id, employee_id, is_active`,
      [employeeId, pinHash]
    );
    return { id: row.id, employeeId: row.employee_id, isActive: row.is_active };
  });
}

// Resolves an Employee by the number they typed, together with their stored
// PIN hash — or null when there is no active Employee with that number, when
// they have no floor credential, or when the credential is switched off. The
// route distinguishes none of these to the caller, which is the point.
async function findCredentialForEmployeeNo(employeeNo) {
  const normalised = normaliseEmployeeNo(employeeNo);
  if (normalised === null) return null;
  const { rows } = await getPool().query(
    `SELECT c.pin_hash, c.is_active AS credential_is_active,
            e.id, e.employee_no, e.display_name, e.is_active AS employee_is_active
       FROM employee_floor_credentials c
       JOIN employees e ON e.id = c.employee_id
      WHERE e.employee_no = $1`,
    [normalised]
  );
  const row = rows[0];
  if (!row || !row.credential_is_active || !row.employee_is_active) return null;
  return {
    pinHash: row.pin_hash,
    employee: { id: row.id, employeeNo: row.employee_no, displayName: row.display_name }
  };
}

// Exchanges a verified Employee for an identification token, returning the
// presentable token once. The token is stored only as its SHA-256.
async function createIdentification({ deviceId, employeeId }) {
  const token = crypto.randomBytes(32).toString('base64url');
  const { rows: [row] } = await getPool().query(
    `INSERT INTO technician_identifications (floor_device_id, employee_id, token_hash, expires_at)
     VALUES ($1, $2, $3, now() + make_interval(secs => $4))
     RETURNING expires_at`,
    [deviceId, employeeId, sha256(token), IDENTIFICATION_TTL_SECONDS]
  );
  return { token, expiresAt: row.expires_at };
}

// Resolves a presented identification token to the Employee it was issued for,
// but only for the device it was issued on and only while it is still inside
// its window. A token presented after expiry, or against a different device,
// resolves to null and the write is refused.
//
// Like findDeviceByCredential above, this is reached from another Module
// through this Module's entry point (issue #201): it is the question "who does
// this device say is standing at it", asked by maintenance's floor writes
// before they attribute anything to anybody.
async function findValidIdentification(token, deviceId) {
  if (typeof token !== 'string' || token === '') return null;
  const { rows } = await getPool().query(
    `SELECT e.id, e.employee_no, e.display_name
       FROM technician_identifications ti
       JOIN employees e ON e.id = ti.employee_id
      WHERE ti.token_hash = $1
        AND ti.floor_device_id = $2
        AND ti.expires_at > now()
        AND e.is_active`,
    [sha256(token), deviceId]
  );
  const row = rows[0];
  if (!row) return null;
  return { id: row.id, employeeNo: row.employee_no, displayName: row.display_name };
}

// Whether a device registered at `deviceOrgUnitId` may read (and write) an
// Org Unit — its own, or anything beneath it. `path <@ device.path` is the
// same ltree containment every subtree query in this codebase uses. A device
// whose Org Unit no longer resolves (it cannot, the FK holds) is refused.
//
// The third question another Module reaches through the entry point (issue
// #201): `org_units` is People's own tree, so the reach of a device placed in
// it is People's to answer, not one for Maintenance to re-derive from the path
// it was handed.
async function deviceReachesOrgUnit(deviceOrgUnitId, targetOrgUnitId) {
  if (parseId(deviceOrgUnitId) === null || parseId(targetOrgUnitId) === null) return false;
  const { rows: [row] } = await getPool().query(
    `SELECT EXISTS (
       SELECT 1
         FROM org_units device
         JOIN org_units target ON target.id = $2
        WHERE device.id = $1
          AND target.path <@ device.path
     ) AS allowed`,
    [deviceOrgUnitId, targetOrgUnitId]
  );
  return row.allowed;
}

module.exports = {
  IDENTIFICATION_TTL_SECONDS,
  createFloorDevice,
  findDeviceByCredential,
  findDeviceContext,
  setEmployeePin,
  findCredentialForEmployeeNo,
  verifyPin,
  createIdentification,
  findValidIdentification,
  deviceReachesOrgUnit
};
