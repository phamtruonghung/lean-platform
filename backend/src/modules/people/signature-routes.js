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
const { requireAdmin } = require('./authorization');
const { getEmployee } = require('./directory');
const { notFound, httpError, parseId, handleError } = require('./errors');
const {
  keepSignature,
  getCurrentSignature,
  getCurrentSignatureDetails,
  removeSignature,
  requireNoAccount
} = require('./signatures');

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

// The administrator's door (issue #320): the same keep/remove reached with
// somebody else's Employee id, for an Employee who holds no Account and so
// cannot set one themselves. Administrator-only, so no Grant is in question.
// Order: id shape, existence (unknown or Departed is a 404), then the 409.
async function activeEmployeeId(req) {
  const id = parseId(req.params.id);
  if (id === null) throw httpError(400, 'id must be a valid Employee id');
  const employee = await getEmployee(id);
  if (!employee.isActive) throw notFound('Employee');
  return id;
}

router.put('/employees/:id/signature', authenticate, requireActive, requireAdmin, async (req, res, next) => {
  try {
    const employeeId = await activeEmployeeId(req);
    await requireNoAccount(employeeId);
    const signature = await keepSignature(req.account.id, employeeId, req.body ?? {});
    res.json({ signature });
  } catch (error) {
    handleError(error, res, next);
  }
});

router.get('/employees/:id/signature', authenticate, requireActive, requireAdmin, async (req, res, next) => {
  try {
    const image = await getCurrentSignature(await activeEmployeeId(req));
    res.set('Cache-Control', 'private, no-cache');
    res.type('image/png').send(image);
  } catch (error) {
    handleError(error, res, next);
  }
});

// Who set the current Signature and whether for the Employee or by them.
router.get('/employees/:id/signature/details', authenticate, requireActive, requireAdmin, async (req, res, next) => {
  try {
    const signature = await getCurrentSignatureDetails(await activeEmployeeId(req));
    res.json({ signature });
  } catch (error) {
    handleError(error, res, next);
  }
});

router.delete('/employees/:id/signature', authenticate, requireActive, requireAdmin, async (req, res, next) => {
  try {
    const employeeId = await activeEmployeeId(req);
    await requireNoAccount(employeeId);
    await removeSignature(req.account.id, employeeId);
    res.status(204).end();
  } catch (error) {
    handleError(error, res, next);
  }
});

module.exports = router;
