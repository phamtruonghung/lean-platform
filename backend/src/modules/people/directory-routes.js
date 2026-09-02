/*
 * The Employee directory, over HTTP (issue #9). Mounted by index.js
 * alongside routes.js's Account surface (issue #6) and plant-routes.js's
 * Sites/Org Unit tree (issue #7), all under `/api/people`.
 *
 * The read surface (GET /employees, GET /employees/me, GET /employees/:id,
 * GET /job-roles) sits behind `authenticate` + `requireActive` only — no
 * `authorization.js` scope check on any of them, deliberately. Unlike a Site
 * or an Org Unit, which a caller must already hold a grant on before
 * plant-routes.js will name it back to them, an Employee reaching one of
 * these routes is never scope-checked: any approved Account may browse the
 * whole directory, list it, search it, filter it, and read any one
 * Employee's detail view or the list of job roles. ADR-0009 is the decision
 * record for why — in short, a plant directory is not a secret the way an
 * Account's own identity (`GET /accounts`, still administrator-only in
 * routes.js) is, and Org Unit scope exists to bound where an Account may
 * *act*, not who it may know about. GET /job-roles rides the same rule: a
 * job role is catalogue data this Module's own detail view already exposes
 * to any reader, so gating the list of possible values behind more than
 * `requireActive` would gate nothing real. Do not add a `canAct`/scope check
 * to any of these "just in case" without reading that ADR first.
 *
 * The write surface (issue #9's criteria 5 and 6, added in this file's
 * second pass, and issue #10's job-role and assignment writes, added in the
 * third) is a different question from "who may know about an Employee" — it
 * is "who may change the payroll/plant record of one" — so POST /employees,
 * PATCH /employees/:id, POST /employees/:id/departure, POST
 * /employees/:id/reinstatement, POST /job-roles, PATCH /job-roles/:id and
 * POST /employees/:id/assignments all sit behind requireAdmin as well. Three
 * of these follow routes.js's own POST /accounts/:id/approval and
 * /rejection (an administrator-only action verb as the last path segment,
 * not a generic PATCH): /departure, /reinstatement and /assignments each
 * name an event worth recording, not an ordinary field edit. PATCH
 * /job-roles/:id is deliberately the other shape — a genuine PATCH, mirroring
 * PATCH /org-units/:id in plant-routes.js, because "deactivate this job
 * role" has no event of its own the way departing an Employee or recording
 * an assignment does; it is exactly the boolean-flag edit a PATCH is for.
 * This is all deliberately administrator-only rather than Org-Unit-scoped,
 * for the same ADR-0009 reason the read surface is unscoped: an Employee is
 * not "owned" by an Org Unit the way a grant is, and neither is a job role
 * or an assignment.
 *
 * There is deliberately no self-service edit route — no PATCH an Account can
 * call against its own linked Employee. Criterion 7 ("a Member can see their
 * own Employee record and cannot edit it after it is first entered") is
 * satisfied by GET /employees/me existing and no write route existing beside
 * it; a Member reaching any of the write routes below gets the same 403
 * requireAdmin gives everyone else who is not an administrator (see test 17,
 * "gets 403 from all four write routes", and issue #10's own 403 test).
 *
 * GET /employees/me (criterion 7) must be declared before GET /employees/:id
 * — Express 5 would otherwise match the literal segment "me" as the :id
 * param, since routes are matched in declaration order and :id matches
 * anything.
 */

const express = require('express');
const { authenticate, requireActive } = require('./middleware');
const { requireAdmin } = require('./authorization');
const { httpError, parseId, handleError } = require('./errors');
const {
  listEmployees,
  getEmployeeDetail,
  createEmployee,
  updateEmployee,
  setEmployeeDeparted,
  reinstateEmployee,
  listJobRoles,
  createJobRole,
  setJobRoleActive,
  assignEmployee
} = require('./directory');

const router = express.Router();

router.get('/employees', authenticate, requireActive, async (req, res, next) => {
  try {
    let orgUnitId;
    if (req.query.orgUnitId !== undefined) {
      orgUnitId = parseId(req.query.orgUnitId);
      if (orgUnitId === null) {
        return res.status(400).json({ message: 'orgUnitId must be a valid Org Unit id' });
      }
    }

    // Same validation shape as orgUnitId above (issue #10, criterion 4).
    let jobRoleId;
    if (req.query.jobRoleId !== undefined) {
      jobRoleId = parseId(req.query.jobRoleId);
      if (jobRoleId === null) {
        return res.status(400).json({ message: 'jobRoleId must be a valid job role id' });
      }
    }

    // Exact string "true" only — `?includeDeparted` with no value, `=false`,
    // or any other string must never widen the listing. A directory listing
    // silently including Departed Employees because of a typo or a stray
    // query param is the failure mode this narrow check avoids; anything
    // else falls back to the safe default (Active only).
    const includeDeparted = req.query.includeDeparted === 'true';

    const employees = await listEmployees({
      search: typeof req.query.search === 'string' ? req.query.search : undefined,
      orgUnitId,
      jobRoleId,
      includeDeparted
    });
    res.json({ employees });
  } catch (error) {
    handleError(error, res, next);
  }
});

// Criterion 7: a Member sees their own Employee record. req.account.employeeId
// is the app_users.employee_id link (service.js's toAccount) — null for an
// Account with none, which is a different fact than "no Employee with this
// id" (getEmployee's own notFound message), so this writes its own 404
// rather than calling into directory.js just to get the generic one.
router.get('/employees/me', authenticate, requireActive, async (req, res, next) => {
  try {
    if (req.account.employeeId === null || req.account.employeeId === undefined) {
      throw httpError(404, 'This Account has no linked Employee record');
    }
    const employee = await getEmployeeDetail(req.account.employeeId);
    res.json({ employee });
  } catch (error) {
    handleError(error, res, next);
  }
});

// The detail view (criterion 4): job role, Org Unit assignments and skills,
// alongside the Employee record itself.
router.get('/employees/:id', authenticate, requireActive, async (req, res, next) => {
  try {
    const id = parseId(req.params.id);
    if (id === null) {
      return res.status(400).json({ message: 'id must be a valid Employee id' });
    }
    const employee = await getEmployeeDetail(id);
    res.json({ employee });
  } catch (error) {
    handleError(error, res, next);
  }
});

// Throws rather than writing the response itself, following routes.js's own
// requireAccountId convention — the surrounding route's try/catch and this
// file's own handleError are what turn the thrown httpError into the 400
// response.
function requireEmployeeId(req) {
  const id = parseId(req.params.id);
  if (id === null) {
    throw httpError(400, 'id must be a valid Employee id');
  }
  return id;
}

// ---------------------------------------------------------------------------
// The write surface (issue #9, criteria 5 and 6) — administrator only. See
// this file's own header for why: unlike the read surface above, this is
// "who may change an Employee's record", not "who may know about one".
// ---------------------------------------------------------------------------

router.post('/employees', authenticate, requireActive, requireAdmin, async (req, res, next) => {
  try {
    const employee = await createEmployee(req.body ?? {}, req.account.id);
    res.status(201).json({ employee });
  } catch (error) {
    handleError(error, res, next);
  }
});

router.patch('/employees/:id', authenticate, requireActive, requireAdmin, async (req, res, next) => {
  try {
    const id = requireEmployeeId(req);
    const employee = await updateEmployee(id, req.body ?? {}, req.account.id);
    res.json({ employee });
  } catch (error) {
    handleError(error, res, next);
  }
});

// Mirrors routes.js's POST /accounts/:id/approval and /rejection: an
// action-verb path segment rather than a generic PATCH, because departing
// (or reinstating) an Employee is an event worth naming, not an ordinary
// field edit — and, per updateEmployee's own comment, PATCH /employees/:id
// above has no way to reach is_active or terminated_on at all, so this is
// the only route that can.
router.post('/employees/:id/departure', authenticate, requireActive, requireAdmin, async (req, res, next) => {
  try {
    const id = requireEmployeeId(req);
    const employee = await setEmployeeDeparted(id, req.body ?? {}, req.account.id);
    res.json({ employee });
  } catch (error) {
    handleError(error, res, next);
  }
});

router.post('/employees/:id/reinstatement', authenticate, requireActive, requireAdmin, async (req, res, next) => {
  try {
    const id = requireEmployeeId(req);
    const employee = await reinstateEmployee(id, req.account.id);
    res.json({ employee });
  } catch (error) {
    handleError(error, res, next);
  }
});

// ---------------------------------------------------------------------------
// Job roles (issue #10, criterion 1). Catalogue data readable by any
// approved Account — see this file's own header for why GET /job-roles is
// not administrator-only the way POST and PATCH are.
// ---------------------------------------------------------------------------

router.get('/job-roles', authenticate, requireActive, async (req, res, next) => {
  try {
    // Same "exact string 'true' only" rule as GET /employees's
    // includeDeparted, and for the same reason.
    const includeInactive = req.query.includeInactive === 'true';
    const jobRoles = await listJobRoles({ includeInactive });
    res.json({ jobRoles });
  } catch (error) {
    handleError(error, res, next);
  }
});

router.post('/job-roles', authenticate, requireActive, requireAdmin, async (req, res, next) => {
  try {
    const jobRole = await createJobRole(req.body ?? {}, req.account.id);
    res.status(201).json({ jobRole });
  } catch (error) {
    handleError(error, res, next);
  }
});

// isActive only — mirrors PATCH /org-units/:id in plant-routes.js exactly:
// deactivation, not deletion, since past assignments still reference the role.
router.patch('/job-roles/:id', authenticate, requireActive, requireAdmin, async (req, res, next) => {
  try {
    const id = parseId(req.params.id);
    if (id === null) {
      return res.status(400).json({ message: 'id must be a valid job role id' });
    }
    if (typeof req.body?.isActive !== 'boolean') {
      return res.status(400).json({ message: 'isActive (boolean) is required' });
    }
    const jobRole = await setJobRoleActive(id, req.body.isActive, req.account.id);
    res.json({ jobRole });
  } catch (error) {
    handleError(error, res, next);
  }
});

// ---------------------------------------------------------------------------
// Assignments (issue #10, criteria 2 and 3) — administrator-only, same
// reasoning as the Employee write surface above.
// ---------------------------------------------------------------------------

router.post('/employees/:id/assignments', authenticate, requireActive, requireAdmin, async (req, res, next) => {
  try {
    const id = requireEmployeeId(req);
    const assignment = await assignEmployee(id, req.body ?? {}, req.account.id);
    res.status(201).json({ assignment });
  } catch (error) {
    handleError(error, res, next);
  }
});

module.exports = router;
