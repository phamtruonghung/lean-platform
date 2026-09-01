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
const { parseId } = require('./plant');
const {
  listAccounts,
  listPendingAccounts,
  approveAccount,
  rejectAccount,
  setAccountActive
} = require('./service');

const router = express.Router();

// A domain error carries its own status (service.js's httpError) and is the
// expected shape for a bad request or a missing Account; anything else is a
// genuine failure and goes to the app's own unhandled-error handler via
// next() — the same split plant-routes.js's own handleError makes.
function handleError(error, res, next) {
  if (error.status) {
    return res.status(error.status).json({ message: error.message });
  }
  return next(error);
}

function requireAccountId(req, res) {
  const id = parseId(req.params.id);
  if (id === null) {
    res.status(400).json({ message: 'id must be a valid Account id' });
    return null;
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
router.get('/accounts', authenticate, requireActive, async (_req, res, next) => {
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
    const id = requireAccountId(req, res);
    if (id === null) return;

    const { role, grants } = req.body ?? {};
    const account = await approveAccount(id, { role, grants: grants ?? [] }, req.account.id);
    res.json({ account });
  } catch (error) {
    handleError(error, res, next);
  }
});

router.post('/accounts/:id/rejection', authenticate, requireActive, requireAdmin, async (req, res, next) => {
  try {
    const id = requireAccountId(req, res);
    if (id === null) return;

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
    const id = requireAccountId(req, res);
    if (id === null) return;

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
