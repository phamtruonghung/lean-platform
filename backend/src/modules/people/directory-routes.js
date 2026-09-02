/*
 * The Employee directory, over HTTP (issue #9). Mounted by index.js
 * alongside routes.js's Account surface (issue #6) and plant-routes.js's
 * Sites/Org Unit tree (issue #7), all under `/api/people`.
 *
 * The read surface (GET /employees, GET /employees/me, GET /employees/:id)
 * sits behind `authenticate` + `requireActive` only — no `authorization.js`
 * scope check on any of them, deliberately. Unlike a Site or an Org Unit,
 * which a caller must already hold a grant on before plant-routes.js will
 * name it back to them, an Employee reaching one of these three is never
 * scope-checked: any approved Account may browse the whole directory, list
 * it, search it, and read any one Employee's detail view. ADR-0009 is the
 * decision record for why — in short, a plant directory is not a secret the
 * way an Account's own identity (`GET /accounts`, still administrator-only
 * in routes.js) is, and Org Unit scope exists to bound where an Account may
 * *act*, not who it may know about. Do not add a `canAct`/scope check to the
 * read surface "just in case" without reading that ADR first.
 *
 * The write surface (issue #9's criteria 5 and 6, added in this file's
 * second pass) is a different question from "who may know about an
 * Employee" — it is "who may change the payroll/plant record of one" — so
 * POST /employees, PATCH /employees/:id, POST /employees/:id/departure and
 * POST /employees/:id/reinstatement all sit behind requireAdmin as well,
 * following routes.js's own POST /accounts/:id/approval and /rejection
 * (same shape: an administrator-only action verb as the last path segment,
 * not a generic PATCH). This is deliberately administrator-only rather than
 * Org-Unit-scoped, for the same ADR-0009 reason the read surface is
 * unscoped: an Employee is not "owned" by an Org Unit the way a grant is.
 *
 * There is deliberately no self-service edit route — no PATCH an Account can
 * call against its own linked Employee. Criterion 7 ("a Member can see their
 * own Employee record and cannot edit it after it is first entered") is
 * satisfied by GET /employees/me existing and no write route existing beside
 * it; a Member reaching any of the four write routes below gets the same
 * 403 requireAdmin gives everyone else who is not an administrator (see
 * test 17, "gets 403 from all four write routes").
 *
 * GET /employees/me (criterion 7) must be declared before GET /employees/:id
 * — Express 5 would otherwise match the literal segment "me" as the :id
 * param, since routes are matched in declaration order and :id matches
 * anything.
 *
 * POST /employees/:id/assignments (issue #10) is a different question again
 * from either of the two above: not "who may know about an Employee" and not
 * "who may change their payroll/plant record", but "who may say where in the
 * plant they work" — which names a particular Org Unit, exactly the shape
 * plant-routes.js already gates by Org Unit scope. So this one route sits
 * behind write scope on the DESTINATION Org Unit (requireAssignmentOrgUnitScope,
 * below) rather than requireAdmin, even though it lives in this file next to
 * routes that are administrator-only. ADR-0010 is the decision record for
 * why this is a deliberate deviation from ADR-0009's reasoning, not an
 * inconsistency: an Org Unit assignment, unlike an Employee record itself,
 * genuinely is "owned" by the Org Unit it names.
 */

const express = require('express');
const { authenticate, requireActive } = require('./middleware');
const authorization = require('./authorization');
const { requireAdmin } = authorization;
const plant = require('./plant');
const { httpError, parseId, handleError, OUTSIDE_GRANTED_ORG_UNITS } = require('./errors');
const {
  listEmployees,
  getEmployeeDetail,
  createEmployee,
  updateEmployee,
  setEmployeeDeparted,
  reinstateEmployee,
  createAssignment
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
// Org Unit assignments (issue #10) — write scope on the DESTINATION Org
// Unit only. See this file's own header and ADR-0010 for why this route is
// gated differently from the rest of the write surface above.
// ---------------------------------------------------------------------------

// Modelled closely on plant-routes.js's requireOrgUnitCreateScope: it too
// reads its Org Unit id out of the body rather than a path param, and
// follows the same existence-before-scope ordering authorization.js
// documents (parse the id, 400 if malformed; plant.getOrgUnit, 404 if it
// names nothing; authorization.canAct, 403 with the shared body if the
// caller holds no write grant reaching it). canAct already returns true
// unconditionally for an administrator, so this needs no separate admin
// check of its own.
//
// Deliberately NOT also requiring scope on the Employee's current (source)
// Org Unit: a supervisor receiving a transfer into their line should not
// need a grant on the line the person is leaving (ADR-0010). The Employee's
// own existence (and whether they have departed) is resolved afterwards, by
// createAssignment itself, inside the route handler below — this middleware
// only ever answers "may this caller write to the named destination".
async function requireAssignmentOrgUnitScope(req, res, next) {
  try {
    const orgUnitId = parseId(req.body?.orgUnitId);
    if (orgUnitId === null) {
      return res.status(400).json({ message: 'orgUnitId must be a valid Org Unit id' });
    }

    const orgUnit = await plant.getOrgUnit(orgUnitId); // throws the 404.
    const allowed = await authorization.canAct({ account: req.account, orgUnitId: orgUnit.id, write: true });
    if (!allowed) {
      return res.status(403).json({ message: OUTSIDE_GRANTED_ORG_UNITS });
    }
    return next();
  } catch (error) {
    return handleError(error, res, next);
  }
}

router.post(
  '/employees/:id/assignments',
  authenticate,
  requireActive,
  requireAssignmentOrgUnitScope,
  async (req, res, next) => {
    try {
      const id = requireEmployeeId(req); // 400 if malformed; createAssignment below 404s if it does not exist.
      const assignment = await createAssignment(id, req.body ?? {}, req.account.id);
      res.status(201).json({ assignment });
    } catch (error) {
      handleError(error, res, next);
    }
  }
);

module.exports = router;
