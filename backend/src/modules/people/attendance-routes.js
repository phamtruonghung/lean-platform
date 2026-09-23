/*
 * The attendance sheet, over HTTP (issue #249). Mounted by index.js alongside
 * routes.js, plant-routes.js, directory-routes.js, job-role-routes.js and
 * skill-routes.js, all under `/api/people`.
 *
 * Two scope rules, ADR-0040's own "Recording needs an edit Grant, and nothing
 * more":
 *
 *   - Reading the sheet is Site-wide: `GET .../attendance-sheet` sits behind
 *     `authenticate` + `requireActive` + `authorization.canSeeSite` about the
 *     shift instance's own Site — any Grant, read or write, on any Org Unit
 *     within it. Issue #249's own criterion: "Reading a sheet needs only
 *     visibility of the Site." That GET also asks `authorization.canAct({
 *     write: true })` about the shift instance's own Org Unit — not as a
 *     gate (a caller who fails it is never refused the read), but to decide
 *     whether `attendance.getAttendanceSheet` may create and pre-fill an
 *     unstarted sheet: opening a sheet is itself the write ADR-0040 calls
 *     "recording needs an edit Grant, and nothing more", so a bare read
 *     Grant must never be enough to author the pre-filled rows or the sheet
 *     row itself. See `attendance.js`'s own header on `canRecord` for the
 *     full reasoning and the `started` field this produces.
 *   - Recording, confirming and correcting are all a write at the shift
 *     instance's own Org Unit: `authorization.canAct({ write: true })`, true
 *     unconditionally for role `admin`. `write: true` is spelled out because
 *     it defaults to FALSE, and a route that forgot it would be authorised
 *     by any read Grant with no error anywhere to notice.
 *
 * Existence before scope, the order AGENTS.md §6 fixes and
 * safety-incident-routes.js's own middleware chain already follows: the
 * shift instance is resolved first (a clean 404, even for an administrator),
 * and only then is its Site's visibility or its Org Unit's write scope
 * asked about — `canAct`/`canSeeSite` both return `true` unconditionally for
 * role `admin` before looking at the id at all, so asking scope first would
 * turn a bad shift instance id into a raw 500 rather than a clean 404.
 * `requireShiftInstanceWriteScope` chains through
 * `requireShiftInstanceVisible` for the same reason
 * `requireSafetyIncidentWriteScope` chains through
 * `requireSafetyIncidentVisible` in that file — a write Grant is asked about
 * only once existence and Site visibility are already settled.
 *
 * GET /absence-reasons is an open read (authenticate + requireActive only),
 * mirroring GET /skills and GET /job-roles exactly: shared reference data
 * every Site draws from, not a thing a caller must already hold a Grant on
 * to be told about (skill-routes.js's own header makes the identical
 * argument for `skills`).
 *
 * GET /attendance-to-confirm (issue #250) is a third scope shape, distinct
 * from both above: not Site-wide visibility and not one shift instance's own
 * write Grant, but "every Org Unit this caller's edit Grants reach, across
 * every Site" — self-filtered the way GET /people/me already is, with no
 * separate 403 gate, since an empty reach is itself an honest (empty)
 * answer. See its own route handler below and attendance.js's
 * `listAttendanceToConfirm` header for the full reasoning.
 */

const express = require('express');
const { authenticate, requireActive } = require('./middleware');
const authorization = require('./authorization');
const plant = require('./plant');
const { notFound, parseId, handleError, httpError, OUTSIDE_GRANTED_ORG_UNITS } = require('./errors');
const attendance = require('./attendance');

const router = express.Router();

async function requireKnownShiftInstance(req, res, next) {
  try {
    const shiftInstance = await attendance.findShiftInstance(req.params.shiftInstanceId);
    if (!shiftInstance) throw notFound('Shift instance');
    req.shiftInstance = shiftInstance;
    return next();
  } catch (error) {
    return handleError(error, res, next);
  }
}

async function requireShiftInstanceVisible(req, res, next) {
  return requireKnownShiftInstance(req, res, async () => {
    const allowed = await authorization.canSeeSite({ account: req.account, siteId: req.shiftInstance.siteId });
    if (!allowed) {
      return res.status(403).json({ message: OUTSIDE_GRANTED_ORG_UNITS });
    }
    return next();
  });
}

async function requireShiftInstanceWriteScope(req, res, next) {
  return requireShiftInstanceVisible(req, res, async () => {
    const allowed = await authorization.canAct({
      account: req.account,
      orgUnitId: req.shiftInstance.orgUnitId,
      write: true
    });
    if (!allowed) {
      return res.status(403).json({ message: OUTSIDE_GRANTED_ORG_UNITS });
    }
    return next();
  });
}

// The Attendance Screen's own picker (issue #249): the shift instances at
// one Org Unit on one production day, so a supervisor can find the sheet
// they mean to open — there is no shift calendar Screen to link from yet
// (#250 is the worklist that will do that job properly). Site-wide read,
// the same `canSeeSite` question every other read in this file asks.
router.get('/org-units/:orgUnitId/shift-instances', authenticate, requireActive, async (req, res, next) => {
  try {
    const orgUnitId = parseId(req.params.orgUnitId);
    if (orgUnitId === null) {
      return res.status(400).json({ message: 'orgUnitId must be a valid Org Unit id' });
    }
    const orgUnit = await plant.getOrgUnit(orgUnitId); // 404s if it does not exist.
    const allowed = await authorization.canSeeSite({ account: req.account, siteId: orgUnit.siteId });
    if (!allowed) {
      return res.status(403).json({ message: OUTSIDE_GRANTED_ORG_UNITS });
    }
    const shiftInstances = await attendance.listShiftInstances(orgUnit.id, { date: req.query.date });
    res.json({ shiftInstances });
  } catch (error) {
    handleError(error, res, next);
  }
});

// The attendance-to-confirm worklist (issue #250): past shift instances
// whose sheet is missing or unconfirmed, oldest first, restricted to the Org
// Units the caller's own edit Grants reach — "the sheets it could confirm"
// (issue #250's own wording) — rather than to Site visibility the way every
// other read in this file is. An administrator holds no Grant rows at all
// (see authorization.js's own header), so it is asked the same `everywhere`
// question `GET /people/me` already answers with `orgUnitScopeFor`, reused
// here rather than a second, narrower query of the same Grant rows —
// AGENTS.md's own "do not re-spell authorization SQL outside People" is
// honoured by staying inside this Module and by reusing an existing
// authorization.js entry point instead of adding a new one.
//
// No separate scope gate on this route: the list already IS the caller's
// own reach, the same self-filtering shape `GET /people/me` has, so a
// caller with no write Grant anywhere sees an empty list (200), never a
// 403 — there is nothing to refuse when the query already answers "nowhere"
// honestly.
const WORKLIST_DATE_PATTERN = /^\d{4}-\d{2}-\d{2}$/;

function requireWorklistQueryDate(field, value) {
  if (value === undefined) return null;
  if (typeof value !== 'string' || !WORKLIST_DATE_PATTERN.test(value)) {
    throw httpError(400, `${field} must be a date in YYYY-MM-DD form`);
  }
  return value;
}

router.get('/attendance-to-confirm', authenticate, requireActive, async (req, res, next) => {
  try {
    // `writeGrantOrgUnitIds === null` means "everywhere" (administrator);
    // otherwise the flattened `orgUnitIds` of every grant carrying
    // `canWrite` — a read-only Grant contributes nothing here, per ADR-0040's
    // "recording needs an edit Grant" (attendance.js's own header on this
    // function explains why).
    let writeGrantOrgUnitIds = null;
    if (!authorization.isAdmin(req.account)) {
      const scope = await authorization.orgUnitScopeFor({ account: req.account });
      const reach = new Set();
      for (const grant of scope.grants) {
        if (!grant.canWrite) continue;
        for (const id of grant.orgUnitIds) reach.add(id);
      }
      writeGrantOrgUnitIds = Array.from(reach);
    }

    let orgUnitPath = null;
    if (req.query.orgUnitId !== undefined) {
      const orgUnit = await plant.getOrgUnit(req.query.orgUnitId); // 404s if it does not exist.
      orgUnitPath = orgUnit.path;
    }

    const from = requireWorklistQueryDate('from', req.query.from);
    const to = requireWorklistQueryDate('to', req.query.to);

    const worklist = await attendance.listAttendanceToConfirm({
      writeGrantOrgUnitIds,
      orgUnitPath,
      from,
      to
    });
    res.json(worklist);
  } catch (error) {
    handleError(error, res, next);
  }
});

router.get('/absence-reasons', authenticate, requireActive, async (req, res, next) => {
  try {
    const includeInactive = req.query.includeInactive === 'true';
    const absenceReasons = await attendance.listAbsenceReasons({ includeInactive });
    res.json({ absenceReasons });
  } catch (error) {
    handleError(error, res, next);
  }
});

router.get(
  '/shift-instances/:shiftInstanceId/attendance-sheet',
  authenticate,
  requireActive,
  requireShiftInstanceVisible,
  async (req, res, next) => {
    try {
      // Whether this GET may create and pre-fill an unstarted sheet — never
      // a refusal on its own (that is `requireShiftInstanceVisible`'s job
      // above); see this file's own header and attendance.js's for why a
      // read Grant is not enough to author the sheet.
      const canRecord = await authorization.canAct({
        account: req.account,
        orgUnitId: req.shiftInstance.orgUnitId,
        write: true
      });
      const result = await attendance.getAttendanceSheet(req.shiftInstance.id, req.account.id, canRecord);
      res.json(result);
    } catch (error) {
      handleError(error, res, next);
    }
  }
);

router.post(
  '/shift-instances/:shiftInstanceId/attendance-sheet/confirm',
  authenticate,
  requireActive,
  requireShiftInstanceWriteScope,
  async (req, res, next) => {
    try {
      const sheet = await attendance.confirmAttendanceSheet(req.shiftInstance.id, req.account.id);
      res.json({ sheet });
    } catch (error) {
      handleError(error, res, next);
    }
  }
);

router.post(
  '/shift-instances/:shiftInstanceId/attendance-records',
  authenticate,
  requireActive,
  requireShiftInstanceWriteScope,
  async (req, res, next) => {
    try {
      const record = await attendance.addStandIn(req.shiftInstance.id, req.body ?? {}, req.account.id);
      res.status(201).json({ record });
    } catch (error) {
      handleError(error, res, next);
    }
  }
);

router.patch(
  '/shift-instances/:shiftInstanceId/attendance-records/:recordId',
  authenticate,
  requireActive,
  requireShiftInstanceWriteScope,
  async (req, res, next) => {
    try {
      const record = await attendance.updateAttendanceRecord(
        req.shiftInstance.id,
        req.params.recordId,
        req.body ?? {},
        req.account.id
      );
      res.json({ record });
    } catch (error) {
      handleError(error, res, next);
    }
  }
);

router.delete(
  '/shift-instances/:shiftInstanceId/attendance-records/:recordId',
  authenticate,
  requireActive,
  requireShiftInstanceWriteScope,
  async (req, res, next) => {
    try {
      await attendance.removeAttendanceRecord(req.shiftInstance.id, req.params.recordId, req.account.id);
      res.status(204).end();
    } catch (error) {
      handleError(error, res, next);
    }
  }
);

module.exports = router;
