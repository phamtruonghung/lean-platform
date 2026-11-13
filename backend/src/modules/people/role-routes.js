/*
 * Roles and permissions, over HTTP (issue #492, ADR-0061). Mounted by index.js
 * alongside the Module's other route files, all under `/api/people`.
 *
 * **Every route here is guarded by a permission code, not by `requireAdmin`.**
 * `ADM_ROLES_DISPLAY` reads the catalogue and the roles; `ADM_ROLES_CHANGE`
 * creates a role, edits what it carries, retires it, and assigns it to an
 * Account. Today the seed gives both codes to the administrator role alone, so
 * the behaviour is exactly `requireAdmin`'s — but the gate is the code, which
 * is what makes delegated role administration possible later without editing
 * this file. ADR-0061 records why the seed does not delegate it yet: an Account
 * holding `ADM_ROLES_CHANGE` can change the set carried by a role it holds,
 * and SAP's own answer to that is the separate `S_USER_AUTH`/`S_USER_GRP`
 * authorization pair, which this slice does not build.
 *
 * **No DELETE on a role.** Retiring is `PATCH isActive=false`, the same
 * deactivation-never-deletion rule job-roles.js follows and ADR-0009 gives for
 * an Employee: a role that was held is history, and `app_user_roles` rows (and
 * the audit trail) still name it.
 *
 * **The permission set is replaced in one request** (`PUT
 * /roles/:id/permissions`) for the reason roles.js's header gives: the editor
 * sends what the administrator just ticked.
 *
 * `PUT /accounts/:id/roles` is the "Assign" button. It is a replace of that
 * Account's explicit assignments and answers with the Account's whole role
 * view, so the dialog redraws from the server rather than from its own guess.
 */

const express = require('express');
const { authenticate, requireActive } = require('./middleware');
const { requirePermission } = require('./authorization');
const { parseId, handleError, httpError } = require('./errors');
const {
  listRoles,
  getRole,
  listPermissions,
  createRole,
  updateRole,
  setRolePermissions,
  accountRoles,
  assignAccountRoles
} = require('./roles');

const router = express.Router();

const mayRead = requirePermission('ADM_ROLES_DISPLAY');
const mayChange = requirePermission('ADM_ROLES_CHANGE');

function requireRoleId(req) {
  const id = parseId(req.params.id);
  if (id === null) {
    // Thrown, not answered here: the surrounding route's handleError turns it
    // into the 400, matching every other route file in this Module.
    throw httpError(400, 'id must be a valid role id');
  }
  return id;
}

router.get('/permissions', authenticate, requireActive, mayRead, async (req, res, next) => {
  try {
    res.json({ permissions: await listPermissions() });
  } catch (error) {
    handleError(error, res, next);
  }
});

router.get('/roles', authenticate, requireActive, mayRead, async (req, res, next) => {
  try {
    // Exact string "true" only — a stray query value must not widen the list
    // past "active only", the same rule job-role-routes.js's includeInactive
    // follows.
    const includeInactive = req.query.includeInactive === 'true';
    res.json({ roles: await listRoles({ includeInactive }) });
  } catch (error) {
    handleError(error, res, next);
  }
});

router.get('/roles/:id', authenticate, requireActive, mayRead, async (req, res, next) => {
  try {
    res.json({ role: await getRole(requireRoleId(req)) });
  } catch (error) {
    handleError(error, res, next);
  }
});

router.post('/roles', authenticate, requireActive, mayChange, async (req, res, next) => {
  try {
    const role = await createRole(req.body ?? {}, req.account.id);
    res.status(201).json({ role });
  } catch (error) {
    handleError(error, res, next);
  }
});

router.patch('/roles/:id', authenticate, requireActive, mayChange, async (req, res, next) => {
  try {
    const role = await updateRole(requireRoleId(req), req.body ?? {}, req.account.id);
    res.json({ role });
  } catch (error) {
    handleError(error, res, next);
  }
});

router.put('/roles/:id/permissions', authenticate, requireActive, mayChange, async (req, res, next) => {
  try {
    const body = req.body ?? {};
    if (!Object.prototype.hasOwnProperty.call(body, 'permissions')) {
      throw httpError(400, 'permissions is required');
    }
    const role = await setRolePermissions(requireRoleId(req), body.permissions, req.account.id);
    res.json({ role });
  } catch (error) {
    handleError(error, res, next);
  }
});

router.get('/accounts/:id/roles', authenticate, requireActive, mayRead, async (req, res, next) => {
  try {
    const id = parseId(req.params.id);
    if (id === null) {
      throw httpError(400, 'id must be a valid Account id');
    }
    res.json(await accountRoles(id));
  } catch (error) {
    handleError(error, res, next);
  }
});

router.put('/accounts/:id/roles', authenticate, requireActive, mayChange, async (req, res, next) => {
  try {
    const id = parseId(req.params.id);
    if (id === null) {
      throw httpError(400, 'id must be a valid Account id');
    }
    const body = req.body ?? {};
    if (!Object.prototype.hasOwnProperty.call(body, 'roleIds')) {
      throw httpError(400, 'roleIds is required');
    }
    res.json(await assignAccountRoles(id, body.roleIds, req.account.id));
  } catch (error) {
    handleError(error, res, next);
  }
});

module.exports = router;
