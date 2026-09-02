/*
 * Role and Org Unit scope enforcement (issue #8, CONTEXT.md's Account,
 * Approval and Org Unit definitions).
 *
 * Four questions this file answers, and nowhere else in the People Module
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
 *   - "Where does this Account's own scope begin in a given Site's tree?" —
 *     a structurally different question from the two above: not "may the
 *     caller act on this one Org Unit" but "which Org Units, in this Site,
 *     are the caller's own entry points into it" (CONTEXT.md's Entry point,
 *     issue #24, ADR-0008) — grantedEntryPointIds below, which
 *     plant-routes.js calls only for a non-administrator browsing a Site's
 *     tree from its root.
 *   - "Where may this Account work, across the whole Platform?" — issue #43,
 *     the caller's own answer to itself rather than a question about one
 *     Org Unit or one Site: orgUnitScopeFor below, with two callers now — GET
 *     /people/me (routes.js), to tell a caller its own reach, and issue #35's
 *     GET /sites/:siteId/org-units/search (plant-routes.js), which reuses the
 *     same raw Grant rows as its scope filter rather than a second, narrower
 *     query of its own. Deliberately not entry points: an administrator
 *     holds no grant rows (the first bullet above), so entry points for one
 *     would come back empty — exactly the "empty reads as nowhere" reading
 *     this function exists to rule out with an explicit `everywhere` flag
 *     instead.
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

// Issue #24: a grant reaches downward only (canAct's `target.path <@
// granted.path`), so an Account granted a single deep Org Unit is invisible
// at the Site's root level — none of the Site's roots are at or beneath
// their grant, so browsing from the top is a dead end even though their own
// branch is real and GET /org-units/:id already honours it once they know
// its id. This answers a different question than canAct: not "can the
// caller act on this one Org Unit" but "where does the caller's own scope
// begin in this Site's tree" — every Org Unit in the Site the caller holds
// any grant on, read or write alike (an entry point is about reaching the
// tree at all, not about what the caller may do once there), that has no
// *other* granted Org Unit of theirs as a proper ancestor.
//
// The NOT EXISTS clause is the overlapping-grants answer issue #24 asks for:
// when the caller holds both a unit and a grant on one of its own
// descendants, the descendant is already reachable by walking down from the
// ancestor, so it is not its own entry point — only the topmost of a chain
// of grants comes back, and each entry point therefore comes back exactly
// once. `ou.path <@ ancestor.path` is the same downward-reachability test
// canAct uses, just asked in the other direction: "is some other granted Org
// Unit an ancestor of this one" rather than "is this Org Unit reachable from
// a grant".
//
// Deliberately no isAdmin short-circuit here, unlike canAct/canSeeSite:
// whether an administrator ever asks this question at all is the caller's
// call to make, not this module's — plant-routes.js's root-level Org Units
// listing already branches on isAdmin before reaching for this at all, so
// this function only ever answers honestly for the Account it is given.
// Returns a plain array of Org Unit ids, no formatted domain rows and no
// ordering: plant.js's listOrgUnitsByIds owns both the row shape and the
// sort_order, name ordering the rest of this Module's list endpoints use —
// this file's own boundary (see the file header) stops here.
async function grantedEntryPointIds({ account, siteId }) {
  const { rows } = await getPool().query(
    `SELECT ou.id
       FROM org_units ou
       JOIN app_user_org_units auo
         ON auo.org_unit_id = ou.id AND auo.app_user_id = $1
      WHERE ou.site_id = $2
        AND NOT EXISTS (
              SELECT 1
                FROM app_user_org_units ancestor_grant
                JOIN org_units ancestor ON ancestor.id = ancestor_grant.org_unit_id
               WHERE ancestor_grant.app_user_id = $1
                 AND ancestor.id <> ou.id
                 -- Belt-and-braces, not load-bearing: ou.site_id = $2 already
                 -- pins the outer row to one Site, and path <@ is only ever
                 -- true within a Site today (an Org Unit's path is a chain
                 -- of its own ancestors' ids, so no cross-Site path can be a
                 -- prefix of another's). Stated explicitly anyway so the two
                 -- halves of this query cannot disagree if an Org Unit were
                 -- ever reparented across Sites in the future.
                 AND ancestor.site_id = ou.site_id
                 AND ou.path <@ ancestor.path
            )`,
    [account.id, siteId]
  );
  return rows.map((row) => row.id);
}

// Issue #43: the caller's own Org Unit scope, across the whole Platform —
// not "may the caller act on this one Org Unit" (canAct) and not "which Org
// Units are the caller's entry points into this one Site"
// (grantedEntryPointIds), but "where does this Account work at all",
// answered once for GET /people/me (routes.js) rather than per-Site. Issue
// #35's Org Unit search reuses the exact same answer as its scope filter —
// see this file's own header for both callers.
//
// Short-circuits on the role, the same way canAct and canSeeSite do and
// unlike grantedEntryPointIds: an administrator holds no grant rows and
// needs none (see the file header), so an empty grant list would read as
// "nowhere" for the one Account that reaches everywhere. The bootstrap
// administrator (service.js) does hold rows, incidentally, for whichever
// Sites existed at its first sign-in — those are a leftover, not the
// source of its reach, so they are deliberately not returned either. The
// invariant a caller may rely on: everywhere === true implies grants is
// always empty, and vice versa.
//
// Returns the caller's raw Grant rows — both a line and a cell beneath it
// can both appear if both are individually granted — deliberately not
// collapsed to entry points; that stays grantedEntryPointIds's own job,
// answered per-Site on demand by GET /sites/:siteId/org-units (ADR-0008).
async function orgUnitScopeFor({ account }) {
  if (isAdmin(account)) return { everywhere: true, grants: [] };

  const { rows } = await getPool().query(
    `SELECT auo.org_unit_id, ou.site_id, auo.can_write
       FROM app_user_org_units auo
       JOIN org_units ou ON ou.id = auo.org_unit_id
      WHERE auo.app_user_id = $1
      ORDER BY ou.site_id, auo.org_unit_id`,
    [account.id]
  );

  return {
    everywhere: false,
    grants: rows.map((row) => ({
      orgUnitId: row.org_unit_id,
      siteId: row.site_id,
      canWrite: row.can_write
    }))
  };
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

module.exports = {
  ROLES,
  isAdmin,
  canAct,
  canSeeSite,
  grantedEntryPointIds,
  orgUnitScopeFor,
  requireAdmin,
  requireOrgUnitScope,
  requireSiteScope
};
