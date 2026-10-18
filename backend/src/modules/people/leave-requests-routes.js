/*
 * Leave requests, over HTTP (issue #265, ADR-0042). Mounted by index.js
 * alongside attendance-routes.js, all under `/api/people`, every route behind
 * `authenticate` + `requireActive`.
 *
 * Who may do what, in one place:
 *
 *   - **Submit** — the caller's own linked Employee always (`app_users.
 *     employee_id`), with no Grant needed. For anyone else — recording on
 *     behalf of an Employee who cannot sign in, which is most of a plant —
 *     an edit Grant reaching the Employee's resolved Org Unit
 *     (`canAct({ write: true })`, ADR-0040's "recording needs an edit Grant"),
 *     true for an administrator, who is the only one who can act for an
 *     Employee with no Org Unit at all.
 *   - **Decide** (approve / reject) — an edit Grant on the request's own Org
 *     Unit snapshot, and never the Employee's own request, administrators
 *     included (the ADR-0013 analog, and Frappe's validate_for_self_approval).
 *   - **Cancel** — only the Account that submitted it, or the Employee's own
 *     linked Account, and only while it is pending.
 *   - **Read one** — the requester, the Employee's own Account, anyone whose
 *     edit Grants reach its Org Unit, or an administrator; anyone else gets a
 *     404, not a 403, so existence is not leaked. This is a deliberate
 *     exception to ADR-0009's open directory: the note may carry health
 *     detail (ADR-0037's precedent), so a leave request is not a directory
 *     fact. The lists apply the same rule as filters.
 *
 * Existence before scope, AGENTS.md section 6: an unknown or invisible id is a
 * 404 first, and only a caller who can see the request is ever told 403.
 * `write: true` is spelled out on every canAct because it defaults to FALSE.
 *
 * `canDecide` and `canCancel` ride on every serialised request, computed for
 * the calling Account, so a client never re-implements these rules.
 */

const express = require('express');
const { authenticate, requireActive } = require('./middleware');
const authorization = require('./authorization');
const directory = require('./directory');
const leave = require('./leave-requests');
const { notFound, parseId, handleError, httpError, OUTSIDE_GRANTED_ORG_UNITS } = require('./errors');

const router = express.Router();

// The Org Units the caller's edit Grants reach, as a Set of id strings — or
// null for "everywhere" (an administrator). A read-only Grant contributes
// nothing: deciding is operational authority over people the caller records
// attendance for, which is an edit Grant (ADR-0040, ADR-0042). Same
// flattening GET /attendance-to-confirm does with `orgUnitScopeFor`.
async function writeReach(account) {
  if (authorization.isAdmin(account)) return null;
  const scope = await authorization.orgUnitScopeFor({ account });
  const reach = new Set();
  for (const grant of scope.grants) {
    if (!grant.canWrite) continue;
    for (const id of grant.orgUnitIds) reach.add(id);
  }
  return reach;
}

function reaches(reach, leaveRequest) {
  if (reach === null) return true;
  return leaveRequest.orgUnit !== null && reach.has(leaveRequest.orgUnit.id);
}

function isOwnEmployee(account, leaveRequest) {
  return account.employeeId != null && leaveRequest.employee.id === account.employeeId;
}

function isRequesterOrSubject(account, leaveRequest) {
  return leaveRequest.requestedBy.id === account.id || isOwnEmployee(account, leaveRequest);
}

function canSee(account, reach, leaveRequest) {
  return isRequesterOrSubject(account, leaveRequest) || reaches(reach, leaveRequest);
}

function withCallerFlags(account, reach, leaveRequest) {
  const pending = leaveRequest.status === 'pending';
  return {
    ...leaveRequest,
    canDecide: pending && reaches(reach, leaveRequest) && !isOwnEmployee(account, leaveRequest),
    canCancel: pending && isRequesterOrSubject(account, leaveRequest)
  };
}

router.post('/leave-requests', authenticate, requireActive, async (req, res, next) => {
  try {
    const body = req.body ?? {};

    // 1. Body shape.
    const absenceReasonId = parseId(body.absenceReasonId);
    if (absenceReasonId === null) {
      return res.status(400).json({ message: 'absenceReasonId must be a valid absence reason id' });
    }
    const startsOn = leave.requireDate('startsOn', body.startsOn);
    const endsOn = leave.requireDate('endsOn', body.endsOn);
    const note = leave.optionalNote('note', body.note);

    // 2. Which Employee: omitted means the caller's own linked Employee.
    let employeeId;
    if (body.employeeId === undefined || body.employeeId === null) {
      if (req.account.employeeId == null) {
        throw httpError(
          400,
          'employeeId is required: this Account is not linked to an Employee, so it has no leave of its own to request'
        );
      }
      employeeId = req.account.employeeId;
    } else {
      employeeId = parseId(body.employeeId);
      if (employeeId === null) {
        return res.status(400).json({ message: 'employeeId must be a valid Employee id' });
      }
    }
    const employee = await directory.getEmployee(employeeId); // 404s for an unknown Employee.

    // 3. Authority, after existence. The Org Unit is resolved once and kept
    // on the request as its snapshot.
    const orgUnitId = await leave.resolveEmployeeOrgUnitId(employee.id);
    if (employee.id !== req.account.employeeId) {
      const allowed = await authorization.canAct({ account: req.account, orgUnitId, write: true });
      if (!allowed) {
        return res.status(403).json({ message: OUTSIDE_GRANTED_ORG_UNITS });
      }
    }

    // 4. Reason, departed Employee, date order and overlap: leave-requests.js.
    const created = await leave.createLeaveRequest(
      { employee, orgUnitId, absenceReasonId, startsOn, endsOn, note },
      req.account.id
    );
    const reach = await writeReach(req.account);
    res.status(201).json({ leaveRequest: withCallerFlags(req.account, reach, created) });
  } catch (error) {
    handleError(error, res, next);
  }
});

router.get('/leave-requests', authenticate, requireActive, async (req, res, next) => {
  try {
    const view = leave.requireView(req.query.view);
    const status = leave.requireStatus(req.query.status);
    const reach = await writeReach(req.account);

    const rows = await leave.listLeaveRequests({
      view,
      status,
      accountId: req.account.id,
      employeeId: req.account.employeeId ?? null,
      reachOrgUnitIds: reach === null ? null : Array.from(reach)
    });
    res.json({ leaveRequests: rows.map((row) => withCallerFlags(req.account, reach, row)) });
  } catch (error) {
    handleError(error, res, next);
  }
});

// Resolves the request and the caller's reach, and 404s a request the caller
// may not see. Shared by the read and all three transitions.
async function loadVisible(req) {
  const leaveRequest = await leave.findLeaveRequest(req.params.id);
  if (!leaveRequest) throw notFound('Leave request');
  const reach = await writeReach(req.account);
  if (!canSee(req.account, reach, leaveRequest)) throw notFound('Leave request');
  return { leaveRequest, reach };
}

router.get('/leave-requests/:id', authenticate, requireActive, async (req, res, next) => {
  try {
    const { leaveRequest, reach } = await loadVisible(req);
    res.json({ leaveRequest: withCallerFlags(req.account, reach, leaveRequest) });
  } catch (error) {
    handleError(error, res, next);
  }
});

// One route per transition (ADR-0019). Scope, then self-decision, then
// status (409 from the UPDATE's own `WHERE status = 'pending'`).
function decisionRoute(decision) {
  return async (req, res, next) => {
    try {
      const { leaveRequest } = await loadVisible(req);
      const allowed = await authorization.canAct({
        account: req.account,
        orgUnitId: leaveRequest.orgUnit?.id ?? null,
        write: true
      });
      if (!allowed) {
        return res.status(403).json({ message: OUTSIDE_GRANTED_ORG_UNITS });
      }
      if (isOwnEmployee(req.account, leaveRequest)) {
        return res.status(403).json({ message: 'You cannot decide your own leave request' });
      }
      const note = leave.optionalNote('note', (req.body ?? {}).note);
      const decided = await leave.decideLeaveRequest(leaveRequest.id, decision, note, req.account.id);
      const reach = await writeReach(req.account);
      res.json({ leaveRequest: withCallerFlags(req.account, reach, decided) });
    } catch (error) {
      handleError(error, res, next);
    }
  };
}

router.post('/leave-requests/:id/approve', authenticate, requireActive, decisionRoute('approved'));
router.post('/leave-requests/:id/reject', authenticate, requireActive, decisionRoute('rejected'));

router.post('/leave-requests/:id/cancel', authenticate, requireActive, async (req, res, next) => {
  try {
    const { leaveRequest } = await loadVisible(req);
    if (!isRequesterOrSubject(req.account, leaveRequest)) {
      return res.status(403).json({
        message: 'Only the Account that submitted a leave request, or the Employee it is for, can cancel it'
      });
    }
    const cancelled = await leave.cancelLeaveRequest(leaveRequest.id, req.account.id);
    const reach = await writeReach(req.account);
    res.json({ leaveRequest: withCallerFlags(req.account, reach, cancelled) });
  } catch (error) {
    handleError(error, res, next);
  }
});

module.exports = router;
