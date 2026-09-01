/*
 * The People Module's Account surface: an Account finding out who it is and
 * whether it may do anything yet (issue #6), and — issue #8 — an
 * administrator working through the queue of Accounts awaiting Approval,
 * admitting one (setting its role and granting its Org Units in the same
 * act), rejecting one, and later deactivating an admitted Account without
 * deleting it. Sites and the Org Unit tree are plant-routes.js's surface
 * (issue #7); Org Unit *scope* enforcement on those routes lives there too,
 * via authorization.js.
 */

const express = require('express');
const { authenticate, requireActive, statusFor } = require('./middleware');
const { requireAdmin } = require('./authorization');
const { parseId, httpError, handleError } = require('./errors');
const {
  listAccounts,
  listPendingAccounts,
  approveAccount,
  rejectAccount,
  setAccountActive
} = require('./service');

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
router.get('/me', authenticate, (req, res) => {
  res.json({
    status: statusFor(req.account),
    account: req.account
  });
});

// Everything else sits behind requireActive. A directory listing is the
// first thing worth protecting this way: real, useful once approved, and
// exactly what an inactive Account must not see.
//
// requireAdmin (issue #8 review): every Account's email, role and
// external_subject (the identity-provider subject) is not something a
// non-admin should be able to enumerate — narrowed here to admin-only rather
// than left open to any active Account. This is a lockdown, not the final
// design; issue #9 ("The directory") is where a wider, deliberate visibility
// rule belongs.
router.get('/accounts', authenticate, requireActive, requireAdmin, async (_req, res, next) => {
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

// The Approval queue itself.
router.get('/accounts/pending', authenticate, requireActive, requireAdmin, async (_req, res, next) => {
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

    const { role, grants } = req.body ?? {};
    const account = await approveAccount(id, { role, grants: grants ?? [] }, req.account.id);
    res.json({ account });
  } catch (error) {
    handleError(error, res, next);
  }
});

router.post('/accounts/:id/rejection', authenticate, requireActive, requireAdmin, async (req, res, next) => {
  try {
    const id = requireAccountId(req);

    const account = await rejectAccount(id, req.account.id);
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

module.exports = router;
