/*
 * Role and Org Unit scope enforcement (issue #8, CONTEXT.md's Account,
 * Approval and Org Unit definitions).
 *
 * Two questions this file answers, and nowhere else in the People Module
 * does:
 *
 *   - "Is this Account an administrator?" — role alone, no grant row in
 *     play at all: an administrator holds no rows in `app_user_org_units`
 *     and needs none, since an administrator can act across every Site
 *     (issue #8's own acceptance criterion) by virtue of the role.
 *   - "Does this Account hold {read,write} scope over this Org Unit?" — a
 *     grant on the unit itself, or on any of its ancestors. `org_units.path`
 *     is an LTREE (see plant.js's own header on why); `target.path <@
 *     granted.path` is true exactly when `target` is `granted`'s own row or
 *     any descendant of it, which is what "a grant on a Site's root Org
 *     Unit reaches every unit beneath it" means as a single indexed (GiST)
 *     lookup rather than a recursive walk up or down the tree.
 *
 * Nothing here is cached, memoised, or stashed on the token: `canAct` and
 * `canSeeSite` query `app_user_org_units` fresh on every call, the same
 * freshness `authenticate` (middleware.js) already gives an Account's own
 * role and `is_active` by re-resolving them from `app_users` per request
 * rather than trusting whatever the caller's token still claims. A grant
 * revoked or added by an administrator therefore takes effect on the
 * caller's very next request (issue #8's own freshness criterion), not
 * when a token happens to expire.
 *
 * A Module internal (ADR-0006): index.js does not re-export this file,
 * since no other Module needs Org Unit scope today — People is the only
 * Module with routes to guard so far. `npm run lint`'s boundary check is
 * the arbiter of that, not this comment.
 */

const { getPool } = require('../../platform/db');
const { parseId, handleError, OUTSIDE_GRANTED_ORG_UNITS } = require('./errors');
const plant = require('./plant');

// Mirrors the CHECK constraint on app_users.role in the baseline
// (`operator`, `supervisor`, `engineer`, `manager`, `admin`). Kept here,
// next to the one place role is treated as an authorization fact, and
// imported by service.js to validate an Approval's requested role — the
// same reasoning as plant.js's own UNIT_TYPES: a bad value should come back
// as a 400 with a clear message, not a raw constraint-violation error.
const ROLES = ['operator', 'supervisor', 'engineer', 'manager', 'admin'];

// The one place "is this Account an administrator?" is spelled out as a role
// comparison — canAct, canSeeSite and requireAdmin below, and the two route
// handlers (plant-routes.js) that need to know whether to skip their own
// per-row filter, all call this rather than writing `role === 'admin'` a
// fifth and sixth time.
function isAdmin(account) {
  return account.role === 'admin';
}

// `true` for role `admin` unconditionally, with no query at all — see the
// file header. Otherwise, a single indexed query: does the caller hold a
// grant, anywhere in `app_user_org_units`, whose Org Unit is `orgUnitId`
// itself or an ancestor of it? `write: true` restricts that to
// `can_write = TRUE` grants only; a read is satisfied by any grant at all,
// since read and write are grantable separately (issue #8's own criterion)
// and a write grant implies read rather than needing its own separate row.
async function canAct({ account, orgUnitId, write = false }) {
  if (isAdmin(account)) return true;
  if (orgUnitId === null || orgUnitId === undefined) return false;

  const { rows } = await getPool().query(
    `SELECT 1
       FROM org_units target
       JOIN app_user_org_units auo ON auo.app_user_id = $1
       JOIN org_units granted ON granted.id = auo.org_unit_id
      WHERE target.id = $2
        AND target.path <@ granted.path
        ${write ? 'AND auo.can_write = TRUE' : ''}
      LIMIT 1`,
    [account.id, orgUnitId]
  );
  return rows.length > 0;
}

// Whether the caller can see this Site at all — used to filter GET /sites
// (plant-routes.js) to what an administrator sees everything of and
// everyone else sees only in part. Distinct from canAct, which answers
// about one particular Org Unit: a Site is visible if the caller holds any
// grant, read or write, on any Org Unit within it, at any depth — not only
// its root, since a grant deeper in the tree still means "I work somewhere
// in this Site" even though it does not reach the whole thing.
async function canSeeSite({ account, siteId }) {
  if (isAdmin(account)) return true;

  const { rows } = await getPool().query(
    `SELECT 1
       FROM app_user_org_units auo
       JOIN org_units ou ON ou.id = auo.org_unit_id
      WHERE auo.app_user_id = $1
        AND ou.site_id = $2
      LIMIT 1`,
    [account.id, siteId]
  );
  return rows.length > 0;
}

// "Must be an administrator" — the Approval queue, approving/rejecting an
// Account, deactivating one, and creating a Site or a root Org Unit are all
// gated on the role alone; no Org Unit is in play yet, so this needs no
// database query of its own. Must run after authenticate() (req.account).
function requireAdmin(req, res, next) {
  if (!isAdmin(req.account)) {
    return res.status(403).json({ message: 'This action requires the administrator role.' });
  }
  return next();
}

// "Must hold {read,write} scope on the Org Unit this route names" —
// issue #8's own 403-vs-404 rule, settled in this order and no other:
// existence first (plant.getOrgUnit's own 404 if the route's id names
// nothing at all), scope second (this middleware's 403 if it names a real
// Org Unit the caller has no grant reaching). Reversing that order would
// let a caller tell an id exists from a 403 where a stranger gets a 404 for
// one that does not — exactly the leak the criterion rules out, so
// existence is always resolved before scope is ever asked about.
//
// `paramName` defaults to the route's own `:id` — every route this guards
// today names its Org Unit that way; the parameter exists so a future route
// with a differently-named param is not forced to rename it to fit here.
function requireOrgUnitScope({ write = false, paramName = 'id' } = {}) {
  return async (req, res, next) => {
    try {
      const orgUnitId = parseId(req.params[paramName]);
      const orgUnit = await plant.getOrgUnit(orgUnitId); // throws the 404.
      const allowed = await canAct({ account: req.account, orgUnitId: orgUnit.id, write });
      if (!allowed) {
        return res.status(403).json({ message: OUTSIDE_GRANTED_ORG_UNITS });
      }
      // The route handler would otherwise re-fetch the exact row this
      // middleware just resolved — stashed here so it does not have to.
      req.orgUnit = orgUnit;
      return next();
    } catch (error) {
      return handleError(error, res, next);
    }
  };
}

// "Must be able to see the Site this route names" — the single-Site
// counterpart to requireOrgUnitScope above, for GET /sites/:siteId
// (plant-routes.js). The list endpoints (GET /sites, GET
// /sites/:siteId/org-units) have nothing to 403 on — a list is filtered
// down to what the caller can see instead — but a single fetch by id is
// exactly the shape where "filter it out of a list" does not apply: either
// the caller can see this one Site or they cannot, so a direct refusal is
// the right shape, following the same existence-before-scope ordering (and
// the same 403 body) as requireOrgUnitScope: plant.getSite's own 404 first
// if the id names no Site at all, then canSeeSite's 403 if it names a real
// Site the caller holds no grant within.
function requireSiteScope({ paramName = 'siteId' } = {}) {
  return async (req, res, next) => {
    try {
      const siteId = parseId(req.params[paramName]);
      const site = await plant.getSite(siteId); // throws the 404.
      const allowed = await canSeeSite({ account: req.account, siteId: site.id });
      if (!allowed) {
        return res.status(403).json({ message: OUTSIDE_GRANTED_ORG_UNITS });
      }
      // The route handler would otherwise re-fetch the exact row this
      // middleware just resolved — stashed here so it does not have to.
      req.site = site;
      return next();
    } catch (error) {
      return handleError(error, res, next);
    }
  };
}

module.exports = { ROLES, isAdmin, canAct, canSeeSite, requireAdmin, requireOrgUnitScope, requireSiteScope };
