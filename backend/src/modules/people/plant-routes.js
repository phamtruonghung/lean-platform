/*
 * Sites and the Org Unit tree, over HTTP (issue #7). Mounted by index.js
 * alongside routes.js's Account surface, both under `/api/people` — see
 * that file's own note on why this belongs in the People Module rather
 * than a Module of its own.
 *
 * Every route here sits behind `authenticate` + `requireActive`, reads
 * included — "browsing the tree" is still something only a signed-in,
 * approved Account should do. On top of that, issue #8 adds role and Org
 * Unit scope enforcement, applied entirely in this file via
 * authorization.js:
 *
 *   - Creating a Site, and creating a *root* Org Unit (one named with no
 *     parentId — the entry point of a whole new branch of a Site's tree),
 *     are administrator-only: `requireOrgUnitCreateScope` below is what
 *     tells those two cases apart from "an Org Unit under an existing
 *     parent", which only needs write scope on that parent.
 *   - Reading or writing a specific Org Unit needs read or write scope on
 *     it (or an ancestor of it) — authorization.js's requireOrgUnitScope,
 *     which also settles issue #8's 403-vs-404 rule: existence before
 *     scope, always, so a caller can never tell "does not exist" apart
 *     from "exists but is out of my scope" from the status code alone.
 *   - GET /sites is the one list endpoint left ungated: nothing to 403 on,
 *     since naming nothing in particular cannot be "out of scope" — it is
 *     instead filtered to what the caller can see, administrator seeing
 *     everything (issue #8's own criterion).
 *   - GET /sites/:siteId and GET /sites/:siteId/org-units, by contrast, both
 *     name one particular Site, which is exactly the shape "filter it out of
 *     a list" does not fit: either the caller can see this Site or they
 *     cannot, so both are gated the same way a single Org Unit is —
 *     authorization.requireSiteScope, existence before scope (404 before
 *     403), rather than silently filtered or (for the Org Units list) left
 *     to fall out as an empty 200. Without this a non-admin could enumerate
 *     Site ids and either read a Site's details directly, or tell "no grant
 *     in this Site" apart from "this Site does not exist" by status code,
 *     even though the Site would never appear in their own filtered GET
 *     /sites list. GET /sites/:siteId/org-units layers a second, narrower
 *     check on top once past that gate: for an explicit parentId, the
 *     returned Org Units are filtered per-row via authorization.canAct,
 *     since being able to see a Site does not mean every Org Unit within it
 *     is in scope too. At the root level (no parentId), a non-administrator
 *     is shown their own entry points into the Site's tree rather than the
 *     Site's root Org Units — issue #24, since a grant reaches downward only
 *     and the Site's roots may not be reachable from it at all. See
 *     authorization.grantedEntryPointIds's own header, and ADR-0008, for why.
 *
 * plant.js itself stays unaware of any of this — see that file's own
 * header.
 */

const express = require('express');
const { authenticate, requireActive } = require('./middleware');
const authorization = require('./authorization');
const plant = require('./plant');
const { parseId, handleError, OUTSIDE_GRANTED_ORG_UNITS } = require('./errors');

const router = express.Router();

// Creating an Org Unit is one route with two different authorization rules,
// which is why this is its own middleware rather than a call to
// authorization.requireOrgUnitScope (built for a route that already names
// its Org Unit in a param, not a body field that may be absent):
//
//   - No parentId in the body: this creates a *root* Org Unit — the start
//     of a new branch of the Site's tree, and therefore of a new grant an
//     administrator would have to hand out afterwards anyway. Administrator
//     only.
//   - A parentId is given: the new unit is created underneath an existing
//     one, so this is exactly "write scope on that Org Unit (or an
//     ancestor of it)" — the same rule PATCH /org-units/:id follows,
//     applied to a body field instead of a route param.
//
// Existence-before-scope (issue #8's 403-vs-404 rule) holds here too: a
// parentId naming nothing at all is a 404, resolved before scope is asked
// about — plant.getOrgUnit's own 404, the same one plant.createOrgUnit
// would eventually hit on its own, just surfaced before any scope check
// rather than after.
async function requireOrgUnitCreateScope(req, res, next) {
  try {
    const parentId = req.body?.parentId;
    if (parentId === undefined || parentId === null) {
      return authorization.requireAdmin(req, res, next);
    }

    const orgUnitId = parseId(parentId);
    if (orgUnitId === null) {
      return res.status(400).json({ message: 'parentId must be a valid Org Unit id' });
    }

    const parent = await plant.getOrgUnit(orgUnitId); // throws the 404.
    const allowed = await authorization.canAct({ account: req.account, orgUnitId: parent.id, write: true });
    if (!allowed) {
      return res.status(403).json({ message: OUTSIDE_GRANTED_ORG_UNITS });
    }
    return next();
  } catch (error) {
    return handleError(error, res, next);
  }
}

router.post('/sites', authenticate, requireActive, authorization.requireAdmin, async (req, res, next) => {
  try {
    const site = await plant.createSite(req.body ?? {}, req.account.id);
    res.status(201).json({ site });
  } catch (error) {
    handleError(error, res, next);
  }
});

// Filtered to what the caller can see (issue #8) — an administrator sees
// every Site; anyone else sees only a Site they hold at least one grant
// within (authorization.js's canSeeSite). Not scope-gated the way a single
// Site or Org Unit is: there is nothing here to 403 on, since a list names
// nothing in particular for a caller to be out of scope of.
router.get('/sites', authenticate, requireActive, async (req, res, next) => {
  try {
    const sites = await plant.listSites();
    if (authorization.isAdmin(req.account)) {
      return res.json({ sites });
    }

    const visible = [];
    for (const site of sites) {
      // Sequential on purpose: each check is its own tiny indexed query,
      // and a Site list is small enough that running them one at a time
      // costs nothing worth a Promise.all's added complexity here.
      // eslint-disable-next-line no-await-in-loop
      if (await authorization.canSeeSite({ account: req.account, siteId: site.id })) {
        visible.push(site);
      }
    }
    res.json({ sites: visible });
  } catch (error) {
    handleError(error, res, next);
  }
});

// Scope-gated (issue #8), unlike the list above: a single fetch by id names
// one particular Site, which is exactly the shape "filter it out of a list"
// does not fit — either the caller can see this Site or they cannot, so a
// direct 403 (403-vs-404, same ordering as authorization.requireOrgUnitScope)
// is the right shape instead. authorization.requireSiteScope already
// resolved and stashed the row on req.site, so there is nothing left for
// this handler to do but return it.
router.get('/sites/:siteId', authenticate, requireActive, authorization.requireSiteScope(), (req, res) => {
  res.json({ site: req.site });
});

// GET /sites/:siteId/org-units             -> see below: an administrator's
//                                              root Org Units, or a
//                                              non-administrator's own entry
//                                              points (issue #24)
// GET /sites/:siteId/org-units?parentId=42 -> Org Unit 42's direct children
// One level per call, which is what "browsed from a Site down to a work
// centre" means here — see getOrgUnitSubtree below for "everything at once".
// Gated on the Site the same way GET /sites/:siteId is — authorization.
// requireSiteScope already resolved existence-before-scope (404 for a Site
// that does not exist, 403 for one the caller holds no grant within at all)
// before this handler runs, closing off a caller telling those two cases
// apart by whether they get an empty 200 list.
//
// Past that gate, an explicit parentId is unchanged from issue #7/#8: the
// direct children, filtered per-row via authorization.canAct for anyone but
// an administrator, on the same reasoning as GET /sites above — a Site being
// visible does not mean every Org Unit within it is, so a caller who passed
// the gate can still legitimately see an empty list here if their grants do
// not reach the requested level of the tree.
//
// The root level (no parentId) is where issue #24 changes the contract for a
// non-administrator: filtering the Site's own root Org Units by canAct the
// same way would leave a caller with only a deep grant seeing nothing, since
// a grant reaches downward only and none of the Site's roots is at or beneath
// it — their own branch unreachable by navigating down from the top, even
// though it is real and reachable directly by id. Rather than filter the
// Site's roots for such a caller, the root level hands back their own entry
// points instead — authorization.grantedEntryPointIds decides which Org
// Unit ids those are (topmost-only, per that function's own header),
// plant.listOrgUnitsByIds turns those ids into rows, two indexed queries
// total. This is a strict generalisation, not a fallback: an Account granted
// a Site's root Org Unit still gets exactly that root back (their one entry
// point is the root itself), so today's behaviour for a shallowly-granted
// Account is unchanged. See ADR-0008 for the full decision and its
// consequences, including that a client can no longer assume a root-level
// row's parentId is null.
router.get('/sites/:siteId/org-units', authenticate, requireActive, authorization.requireSiteScope(), async (req, res, next) => {
  try {
    const siteId = req.site.id;
    let parentId;
    if (req.query.parentId !== undefined) {
      parentId = parseId(req.query.parentId);
      if (parentId === null) {
        return res.status(400).json({ message: 'parentId must be a valid Org Unit id' });
      }
    }

    if (parentId === undefined && !authorization.isAdmin(req.account)) {
      const entryPointIds = await authorization.grantedEntryPointIds({ account: req.account, siteId });
      const orgUnits = await plant.listOrgUnitsByIds(entryPointIds);
      return res.json({ orgUnits });
    }

    const orgUnits = await plant.listOrgUnits(siteId, parentId);
    if (authorization.isAdmin(req.account)) {
      return res.json({ orgUnits });
    }

    const visible = [];
    for (const orgUnit of orgUnits) {
      // eslint-disable-next-line no-await-in-loop
      if (await authorization.canAct({ account: req.account, orgUnitId: orgUnit.id, write: false })) {
        visible.push(orgUnit);
      }
    }
    res.json({ orgUnits: visible });
  } catch (error) {
    handleError(error, res, next);
  }
});

router.post('/sites/:siteId/org-units', authenticate, requireActive, requireOrgUnitCreateScope, async (req, res, next) => {
  try {
    const siteId = parseId(req.params.siteId);
    const orgUnit = await plant.createOrgUnit(siteId, req.body ?? {}, req.account.id);
    res.status(201).json({ orgUnit });
  } catch (error) {
    handleError(error, res, next);
  }
});

// Read scope on the named Org Unit (or an ancestor of it) — issue #8's
// 403-vs-404 rule applied via authorization.requireOrgUnitScope, which
// already resolved and stashed the row on req.orgUnit, so there is nothing
// left for this handler to do but return it.
router.get(
  '/org-units/:id',
  authenticate,
  requireActive,
  authorization.requireOrgUnitScope({ write: false }),
  (req, res) => {
    res.json({ orgUnit: req.orgUnit });
  }
);

// Everything beneath the given Org Unit, itself included, in one request —
// the issue's own acceptance criterion. Same read-scope rule as above.
router.get(
  '/org-units/:id/subtree',
  authenticate,
  requireActive,
  authorization.requireOrgUnitScope({ write: false }),
  async (req, res, next) => {
    try {
      res.json({ orgUnits: await plant.getOrgUnitSubtree(req.orgUnit.id) });
    } catch (error) {
      handleError(error, res, next);
    }
  }
);

// Deactivation, not deletion — the only field this route ever changes.
// Write scope on the named Org Unit (or an ancestor of it).
router.patch(
  '/org-units/:id',
  authenticate,
  requireActive,
  authorization.requireOrgUnitScope({ write: true }),
  async (req, res, next) => {
    try {
      if (typeof req.body?.isActive !== 'boolean') {
        return res.status(400).json({ message: 'isActive (boolean) is required' });
      }
      const orgUnit = await plant.setOrgUnitActive(req.orgUnit.id, req.body.isActive, req.account.id);
      res.json({ orgUnit });
    } catch (error) {
      handleError(error, res, next);
    }
  }
);

module.exports = router;
