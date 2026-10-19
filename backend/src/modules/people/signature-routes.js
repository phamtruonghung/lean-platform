/*
 * An Employee's own Signature over HTTP (issue #317, ADR-0052). Mounted by
 * index.js beside the other People route files under `/api/people`.
 *
 * Every route here is the caller's own: it resolves the Employee the
 * caller's Account is linked to (`app_users.employee_id`) and never takes an
 * Employee id or a Signature id from the request, so nobody can set, read or
 * remove a mark on another person's behalf. No `write: true` and no Grant is
 * needed - the Signature is the person's own, not a record at an Org Unit.
 * An Account linked to no Employee (an administrator need not be one) has no
 * Signature to keep: every route answers 404 for it.
 */

const express = require('express');
const { authenticate, requireActive } = require('./middleware');
const { notFound, handleError } = require('./errors');
const { keepSignature, getCurrentSignature, removeSignature } = require('./signatures');

const router = express.Router();

function ownEmployeeId(req) {
  const employeeId = req.account.employeeId;
  if (employeeId === null || employeeId === undefined) {
    throw notFound('Employee for this Account');
  }
  return employeeId;
}

router.put('/me/signature', authenticate, requireActive, async (req, res, next) => {
  try {
    const signature = await keepSignature(req.account.id, ownEmployeeId(req), req.body ?? {});
    res.json({ signature });
  } catch (error) {
    handleError(error, res, next);
  }
});

router.get('/me/signature', authenticate, requireActive, async (req, res, next) => {
  try {
    const image = await getCurrentSignature(ownEmployeeId(req));
    res.set('Cache-Control', 'private, no-cache');
    res.type('image/png').send(image);
  } catch (error) {
    handleError(error, res, next);
  }
});

router.delete('/me/signature', authenticate, requireActive, async (req, res, next) => {
  try {
    await removeSignature(req.account.id, ownEmployeeId(req));
    res.status(204).end();
  } catch (error) {
    handleError(error, res, next);
  }
});

module.exports = router;
