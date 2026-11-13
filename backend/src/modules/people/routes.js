/*
 * The People Module's Account surface: an Account finding out who it is and
 * whether it may do anything yet (issue #6), and — issue #8 — an
 * administrator working through the queue of Accounts awaiting Approval,
 * admitting one (setting its role and granting its Org Units in the same
 * act), rejecting one, and later deactivating an admitted Account without
 * deleting it. Sites and the Org Unit tree are plant-routes.js's surface
 * (issue #7); Org Unit *scope* enforcement on those routes lives there too,
 * via authorization.js. Issue #270 adds passwords: an administrator resetting
 * an Account's, and a person changing their own (passwords.js).
 */

const express = require('express');
const { authenticate, requireActive, statusFor } = require('./middleware');
const { requireAdmin, requirePermission, orgUnitScopeFor, permissionsForAccount } = require('./authorization');
const { parseId, httpError, handleError } = require('./errors');
const {
  listAccounts,
  listPendingAccounts,
  approveAccount,
  rejectAccount,
  setAccountActive,
  setAccountEmployee
} = require('./service');
const { resetPassword, changeOwnPassword, mustChangePassword } = require('./passwords');

const router = express.Router();

// Throws rather than writing the response itself, following plant.js's own
// requireNonEmptyString convention — the surrounding route's try/catch and
// this file's own handleError (above) are what turn the thrown httpError
// into the 400 response; a caller of this function no longer needs its own
// `if (id === null) return;` guard.
function requireAccountId(req) {
  const id = parseId(req.params.id);
  if (id === null) {
    throw httpError(400, 'id must be a valid Account id');
  }
  return id;
}

// The one endpoint an inactive Account may call: its own status. No
// requireActive here on purpose — that is exactly the gate this route exists
// to be exempt from. `statusFor` (middleware.js) is what tells a pending
// Account apart from a rejected or deactivated one — see that file's own
// header.
//
// `orgUnitScope` (issue #43) sits beside `account`, not inside it, for the
// same reason `status` already does: it is a computed fact about the caller,
// not an `app_users` column, and `toAccount`'s row shape (service.js) is
// shared verbatim by three other endpoints (GET /accounts, approval,
// rejection) that must not be forked to carry it. No branch on status here
// either — orgUnitScopeFor runs for a pending or deactivated caller exactly
// as it does for an active one, computing whatever their real (possibly
// empty) grant rows are; `status` already says they may not act, and
// requireActive blocks every other endpoint.
//
// Entry points are deliberately NOT computed here, for every Site the caller
// can see, eagerly, on every call to this route: that is a structurally
// different, per-Site question ("where does my scope begin in *this* Site's
// tree", CONTEXT.md's Entry point, ADR-0008) that GET /sites/:siteId/org-units
// already answers on demand, and computing it for every visible Site here
// would be O(number of visible Sites) queries on a route that runs on every
// session resolution. See authorization.js's own header and orgUnitScopeFor.
//
// What this route DOES carry, per Grant, is the set of Org Units that Grant
// reaches — the granted unit plus its descendants (issue #110, ADR-0027),
// computed inside orgUnitScopeFor's own query. That is not the same question
// as an entry point ("where does my scope begin" versus "what is inside my
// scope"), it is bounded by the caller's own Grant count rather than a Site
// count, and it is what lets a Screen count work beneath a Grant without
// walking the tree on the client.
router.get('/me', authenticate, async (req, res, next) => {
  try {
    const { permissions, roles } = await permissionsForAccount(req.account);
    res.json({
      status: statusFor(req.account),
      account: { ...req.account, mustChangePassword: await mustChangePassword(req.account.id) },
      orgUnitScope: await orgUnitScopeFor({ account: req.account }),
      // The caller's own effective permissions (issue #492, ADR-0061): every
      // code this Account may use, and the role codes that got it there. The
      // client filters its sidebar on the codes rather than on the role string,
      // which is what makes an administrator's edit to a role visible without
      // a release. Computed here rather than folded into `account` because —
      // like `orgUnitScope` above — it is a fact about the caller right now,
      // not a column on `app_users`.
      permissions,
      roles
    });
  } catch (error) {
    handleError(error, res, next);
  }
});

// "May this Account read every Account, and the Grants each holds?" — ADR-0061's
// model, asked as the code rather than as a role comparison. `requireAdmin`
// answered this door until slice 8; `ADM_ACCOUNTS_DISPLAY` is seeded on
// `ROLE_ADMIN` alone, so the answer is unchanged for every caller — what
// changed is that an administrator can now take the Accounts register off a
// role, which is the point of the model. The five writes below still ask
// `requireAdmin`: each needs its own choice between `ADM_APPROVALS_DECIDE` and
// `ADM_ACCOUNTS_CHANGE`, and that is a decision this slice does not make.
const mayDisplayAccounts = requirePermission('ADM_ACCOUNTS_DISPLAY');

// Everything else sits behind requireActive. A directory listing is the
// first thing worth protecting this way: real, useful once approved, and
// exactly what an inactive Account must not see.
//
// The code (issue #8 review, ADR-0061 slice 8): every Account's email, role
// and external_subject (the identity-provider subject) is not something an
// ordinary Account should be able to enumerate — narrowed here to
// administrators rather than left open to any active Account. This is a
// lockdown, not the final design; issue #9 ("The directory") is where a
// wider, deliberate visibility rule belongs.
router.get('/accounts', authenticate, requireActive, mayDisplayAccounts, async (_req, res, next) => {
  try {
    const accounts = await listAccounts();
    res.json({ accounts });
  } catch (error) {
    handleError(error, res, next);
  }
});

// ---------------------------------------------------------------------------
// Approval (issue #8) — administrator only, throughout: an Account admitted
// by mistake, or one whose role or grants were set wrong, is a much cheaper
// problem than an unapproved caller reaching any of these.
// ---------------------------------------------------------------------------

// The Approval queue itself — the same `ADM_ACCOUNTS_DISPLAY` door as the
// register above: it lists Accounts and the role each was admitted with.
router.get('/accounts/pending', authenticate, requireActive, mayDisplayAccounts, async (_req, res, next) => {
  try {
    res.json({ accounts: await listPendingAccounts() });
  } catch (error) {
    handleError(error, res, next);
  }
});

// Sets role and grants in the same act (issue #8's own criterion — see
// service.js's approveAccount for the single transaction that makes a
// partial Approval unobservable).
router.post('/accounts/:id/approval', authenticate, requireActive, requireAdmin, async (req, res, next) => {
  try {
    const id = requireAccountId(req);

    const { role, grants, employeeId } = req.body ?? {};
    // `expectedApprovalStatus` is optional, exactly as on the rejection route
    // below — see service.js's rejectAccount for what sending it buys an
    // administrator working the queue. `employeeId` is optional too (issue
    // #115) — omitted from the body via destructuring is `undefined`, which
    // approveAccount's own parseOptionalEmployeeId treats as "leave the
    // existing link untouched", distinct from an explicit `null` ("clear
    // it") — so this is passed through as-is, never defaulted the way
    // `grants` is.
    const account = await approveAccount(id, { role, grants: grants ?? [], employeeId }, req.account.id, {
      expectedApprovalStatus: req.body?.expectedApprovalStatus
    });
    res.json({ account });
  } catch (error) {
    handleError(error, res, next);
  }
});

router.post('/accounts/:id/rejection', authenticate, requireActive, requireAdmin, async (req, res, next) => {
  try {
    const id = requireAccountId(req);

    // `expectedApprovalStatus` is optional — see service.js's rejectAccount
    // for what sending it buys an administrator working the queue.
    const account = await rejectAccount(id, req.account.id, {
      expectedApprovalStatus: req.body?.expectedApprovalStatus
    });
    res.json({ account });
  } catch (error) {
    handleError(error, res, next);
  }
});

// Deactivation (or reactivation), not deletion — issue #8's own criterion,
// restricted to an already-approved Account (service.js's setAccountActive).
router.patch('/accounts/:id', authenticate, requireActive, requireAdmin, async (req, res, next) => {
  try {
    const id = requireAccountId(req);

    if (typeof req.body?.isActive !== 'boolean') {
      return res.status(400).json({ message: 'isActive (boolean) is required' });
    }
    const account = await setAccountActive(id, req.body.isActive, req.account.id);
    res.json({ account });
  } catch (error) {
    handleError(error, res, next);
  }
});

// The Employee link's own correction route (issue #115, ADR-0022): sets or
// clears app_users.employee_id outside of Approval — a suggestion an
// administrator missed at Approval time, an Employee record created after
// the Account, or a mistaken link. `employeeId: null` clears it; any other
// value is validated the same way approveAccount's own employeeId is
// (service.js's requireLinkableEmployee, shared by both writers).
//
// refuseSelfAction (service.js) runs as setAccountEmployee's own first
// statement — ADR-0013's rule, extended here (see ADR-0022): asserting which
// Employee an Account belongs to is exactly the kind of identity claim that
// ADR-0013 already refuses an administrator making about their own Account.
router.put('/accounts/:id/employee', authenticate, requireActive, requireAdmin, async (req, res, next) => {
  try {
    const id = requireAccountId(req);

    if (!Object.prototype.hasOwnProperty.call(req.body ?? {}, 'employeeId')) {
      return res.status(400).json({ message: 'employeeId is required (a valid Employee id, or null to clear the link)' });
    }
    const account = await setAccountEmployee(id, req.body.employeeId, req.account.id);
    res.json({ account });
  } catch (error) {
    handleError(error, res, next);
  }
});

// An administrator sets another Account's password (issue #270). ADR-0013's
// refusal applies: not their own. The body's password is never echoed.
router.post('/accounts/:id/password', authenticate, requireActive, requireAdmin, async (req, res, next) => {
  try {
    const id = requireAccountId(req);
    const account = await resetPassword(id, req.body?.password, req.account.id);
    res.json({ account });
  } catch (error) {
    handleError(error, res, next);
  }
});

// A person changes their own password (issue #270). A wrong current password
// is a 400, never a 401: a 401 makes the client sign the person out.
router.put('/me/password', authenticate, requireActive, async (req, res, next) => {
  try {
    const { currentPassword, newPassword } = req.body ?? {};
    const account = await changeOwnPassword(req.account.id, { currentPassword, newPassword }, req.sessionId ?? null);
    res.json({ account });
  } catch (error) {
    handleError(error, res, next);
  }
});

module.exports = router;
