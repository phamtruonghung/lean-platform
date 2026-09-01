/*
 * The People Module's HTTP surface, issue #6's slice of it: an Account
 * finding out who it is and whether it may do anything yet, and an active
 * Account listing the directory. Roles and Approval itself (an administrator
 * activating another Account) are issue #8's, not this one's.
 */

const express = require('express');
const { authenticate, requireActive } = require('./middleware');
const { listAccounts } = require('./service');

const router = express.Router();

// The one endpoint an inactive Account may call: its own status. No
// requireActive here on purpose — that is exactly the gate this route exists
// to be exempt from.
router.get('/me', authenticate, (req, res) => {
  res.json({
    status: req.account.isActive ? 'active' : 'pending_approval',
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
    next(error);
  }
});

module.exports = router;
