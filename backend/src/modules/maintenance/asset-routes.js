/*
 * The Asset register over HTTP (issue #56). Mounted by index.js under
 * `/api/maintenance`.
 *
 * This is the one file in the Module that talks to People, and it does so
 * only through `modules/people`'s entry point (ADR-0006): `authenticate`,
 * `requireActive`, `findSite`, `findOrgUnit`, `canAct` and the shared
 * `OUTSIDE_GRANTED_ORG_UNITS` wording. Everything else about an Asset is
 * assets.js's own business.
 *
 * Two scope rules, and they are deliberately different (#55):
 *
 *   - Reads are Site-wide. GET /sites/:siteId/assets sits behind
 *     `authenticate` + `requireActive` and nothing else — no role check, no
 *     Grant filter, no per-row canAct. ADR-0009 already settled the
 *     reasoning for the Employee directory: Org Unit scope decides where an
 *     Account may act, not who it may know about, and a supervisor who
 *     cannot see the line beside theirs cannot plan around it. Note this is
 *     NOT how People's own GET /sites/:siteId/org-units behaves, which is
 *     requireSiteScope'd — the difference is the point, not an oversight.
 *   - Writes are branch-scoped. POST /assets requires a write Grant reaching
 *     the Org Unit the Asset is placed at.
 *
 * `requireKnownSite` and `requireOrgUnitWriteScope` below are the two
 * middlewares that carry those rules. Both resolve existence BEFORE asking
 * about scope, which is issue #8's own 403-vs-404 ordering, and here it is
 * load-bearing for a second reason People's own call sites never faced:
 * `canAct` returns true for role `admin` before it checks whether the Org
 * Unit id is null at all, so asking it first would turn an administrator's
 * typo into a 500 on a NOT NULL foreign key rather than a clean 404.
 *
 * `requireAssetWriteScope` (issue #61) is a third middleware, and it cannot
 * reuse `requireOrgUnitWriteScope` above: that one parses `req.body.orgUnitId`,
 * which is the right source for POST /assets (the caller is naming where a
 * brand new Asset goes) but wrong for PATCH /assets/:id, whose Org Unit is
 * read off the Asset ROW, not the URL or the body — retirement and nesting
 * never move an Asset, so the row is the only thing that can say where the
 * caller must be entitled to act. Issue #171's own `orgUnitId` on PATCH is a
 * different question asked of a different record — where the Asset is GOING —
 * and it is checked in the route, on top of this middleware rather than
 * instead of it: the Asset's current placement still decides the first half.
 */

const express = require('express');
const people = require('../people');
const assets = require('./assets');
const { parseId, notFound, handleError } = require('./errors');

const router = express.Router();

// The Site a listing names must exist, whoever is asking — a 404, never a
// silently empty 200. Two reasons, both about consistency rather than
// secrecy: People's own GET /sites/:siteId/org-units already 404s an unknown
// Site (authorization.requireSiteScope -> plant.getSite), and an empty list
// for a Site that does not exist is indistinguishable from a real Site with
// no Assets, which is a lie a client cannot recover from. Nothing leaks by
// answering honestly here: this Module's reads are Site-wide by decision, so
// a caller who reaches this route is already entitled to every Asset in
// every Site, and the existence of a Site id is strictly less than that.
async function requireKnownSite(req, res, next) {
  try {
    const site = await people.findSite(req.params.siteId);
    if (!site) throw notFound('Site');
    req.site = site;
    return next();
  } catch (error) {
    return handleError(error, res, next);
  }
}

// Write scope on the Org Unit named in the body — the same rule People's own
// requireOrgUnitCreateScope applies to a parentId, applied to an Asset's
// placement. `write: true` is passed explicitly and must stay that way:
// canAct's `write` defaults to FALSE, so dropping it would silently authorise
// this write for any read Grant, with no error anywhere to notice.
async function requireOrgUnitWriteScope(req, res, next) {
  try {
    const orgUnitId = parseId(req.body?.orgUnitId);
    if (orgUnitId === null) {
      return res.status(400).json({ message: 'orgUnitId must be a valid Org Unit id' });
    }
    const orgUnit = await people.findOrgUnit(orgUnitId);
    if (!orgUnit) throw notFound('Org Unit');

    const allowed = await people.canAct({ account: req.account, orgUnitId: orgUnit.id, write: true });
    if (!allowed) {
      return res.status(403).json({ message: people.OUTSIDE_GRANTED_ORG_UNITS });
    }
    req.orgUnit = orgUnit;
    return next();
  } catch (error) {
    return handleError(error, res, next);
  }
}

// Write scope on the Org Unit the ASSET NAMED IN THE URL already sits at
// (issue #61) — the counterpart to requireOrgUnitWriteScope above for a
// route keyed on an Asset id rather than an Org Unit id in the body.
// Existence before scope, same ordering, same reason: assets.findAsset is
// now total (issue #61's own fix — see that function's own comment), so a
// malformed :id resolves to a clean 404 here rather than ever reaching
// canAct or the database again. `write: true` is passed explicitly and must
// stay that way, for the exact reason requireOrgUnitWriteScope's own comment
// gives: canAct's `write` defaults to FALSE, so dropping it would silently
// authorise this write for any read Grant, with no error anywhere to notice.
async function requireAssetWriteScope(req, res, next) {
  try {
    const asset = await assets.findAsset(req.params.id);
    if (!asset) throw notFound('Asset');

    const allowed = await people.canAct({ account: req.account, orgUnitId: asset.orgUnitId, write: true });
    if (!allowed) {
      return res.status(403).json({ message: people.OUTSIDE_GRANTED_ORG_UNITS });
    }
    req.asset = asset;
    return next();
  } catch (error) {
    return handleError(error, res, next);
  }
}

router.get(
  '/sites/:siteId/assets',
  people.authenticate,
  people.requireActive,
  requireKnownSite,
  async (req, res, next) => {
    try {
      // Only the exact string 'true' counts (issue #61). Anything else —
      // absent, 'false', or garbage like 'yes' — means "no": this is a
      // convenience filter over an already-visible register (reads are
      // Site-wide by decision, see this file's own header), not a value a
      // caller could be wrong about in a way worth a 400 for. Silently
      // treating garbage as "no" is honest here in a way it would not be for
      // an id or an enum, where a bad value could hide a real mistake.
      const includeRetired = req.query.includeRetired === 'true';
      res.json({ assets: await assets.listAssetsAtSite(req.site.id, { includeRetired }) });
    } catch (error) {
      handleError(error, res, next);
    }
  }
);

// No `:siteId` in this path, unlike People's POST /sites/:siteId/org-units:
// `assets` has no site_id column at all. An Asset's Site is whichever Site
// its Org Unit belongs to, so naming one in the URL would be a second source
// of truth to keep agreeing with the first. Issue #57's work orders are the
// same shape for the same reason (work_orders.org_unit_id is filled by
// trigger from the Asset), so POST /work-orders will match this.
router.post(
  '/assets',
  people.authenticate,
  people.requireActive,
  requireOrgUnitWriteScope,
  async (req, res, next) => {
    try {
      const asset = await assets.createAsset(
        { ...(req.body ?? {}), orgUnitId: req.orgUnit.id },
        req.account.id
      );
      res.status(201).json({ asset });
    } catch (error) {
      handleError(error, res, next);
    }
  }
);

// PATCH /assets/:id (issue #61): retiring/reinstating, nesting/detaching and
// — since issue #171 — moving to another Org Unit, all through this one route.
// isActive, parentId and orgUnitId are just three columns on the same Asset
// row, not three resources. Exactly one of them must be present in the body;
// an empty `{}` is refused with 400 rather than accepted as a no-op, the same
// shape PATCH /org-units/:id follows for its own single field.
//
// `hasOwnProperty` is used for `parentId` rather than a truthiness check on
// `req.body.parentId`, on purpose: `parentId: null` (detach — make this
// Asset top-level again) and `parentId` simply absent (leave the parent
// alone) have to read differently, and `!req.body.parentId` cannot tell them
// apart — both are falsy.
//
// A body naming MORE THAN ONE of the three is refused with 400 (issue #61
// review, Fix A; widened to the third field by issue #171).
// setAssetParent, setAssetActive and setAssetOrgUnit are separate
// transactions; a combined PATCH could commit the re-parent and then hit a
// 409 or 500 on the retire half, and the caller — seeing only the failure —
// would reasonably conclude nothing happened, when the parent had already
// changed. These are distinct operations on the same row, not one compound
// edit: nothing asks for them to be combined, and the only sound alternative —
// restructuring three service functions to accept a caller-supplied
// transaction so they could commit together — would be built for a caller that
// does not exist. Refusing is honest; half-committing is not. Send them as
// separate requests.
//
// The extra parent-scope rule below requires write scope on the Org Unit of
// whichever parent is losing OR gaining the Asset when parentId changes —
// the CURRENT parent (detach, move) as well as the PROPOSED parent (attach,
// move) — not just requireAssetWriteScope's own check on the Asset being
// patched. The baseline's own schema comment on assets.parent_id says a
// component's failures roll up to the machine it is part of, so this cuts
// both ways: attaching changes what the new parent is made of, and detaching
// changes what the OLD parent is made of just as much — there IS a second
// machine whose composition changes. Without the current-parent half of this
// check, a supervisor holding write scope only over Line A's Org Unit could
// strip one of Line B's components off a Line B machine using a Grant that
// never reached Line B at all. Being entitled to act on the child is not
// enough to alter either parent.
router.patch(
  '/assets/:id',
  people.authenticate,
  people.requireActive,
  requireAssetWriteScope,
  async (req, res, next) => {
    try {
      const body = req.body ?? {};
      const hasIsActive = Object.prototype.hasOwnProperty.call(body, 'isActive');
      const hasParentId = Object.prototype.hasOwnProperty.call(body, 'parentId');
      const hasOrgUnitId = Object.prototype.hasOwnProperty.call(body, 'orgUnitId');
      const named = [hasIsActive, hasParentId, hasOrgUnitId].filter(Boolean).length;
      if (named === 0) {
        return res.status(400).json({ message: 'isActive, parentId and/or orgUnitId is required' });
      }
      if (named > 1) {
        return res.status(400).json({
          message:
            'only one of isActive, parentId and orgUnitId can be changed per request; send them as separate requests'
        });
      }
      if (hasIsActive && typeof body.isActive !== 'boolean') {
        return res.status(400).json({ message: 'isActive (boolean) is required' });
      }

      if (hasParentId) {
        if (req.asset.parentId !== null) {
          const currentParent = await assets.findAsset(req.asset.parentId);
          if (currentParent) {
            const allowedOnCurrentParent = await people.canAct({
              account: req.account,
              orgUnitId: currentParent.orgUnitId,
              write: true
            });
            if (!allowedOnCurrentParent) {
              return res.status(403).json({ message: people.OUTSIDE_GRANTED_ORG_UNITS });
            }
          }
        }

        if (body.parentId !== null) {
          const parentId = parseId(body.parentId);
          if (parentId === null) {
            return res.status(400).json({ message: 'parentId must be a valid Asset id' });
          }
          const parentAsset = await assets.findAsset(parentId);
          if (!parentAsset) throw notFound('Parent Asset');

          const allowedOnParent = await people.canAct({
            account: req.account,
            orgUnitId: parentAsset.orgUnitId,
            write: true
          });
          if (!allowedOnParent) {
            return res.status(403).json({ message: people.OUTSIDE_GRANTED_ORG_UNITS });
          }
        }
      }

      // The destination Org Unit (issue #171). Existence before scope — the
      // order AGENTS.md §6 fixes and this file's own middlewares follow: a
      // malformed id is a 400, an unknown Org Unit a 404 even for an
      // administrator, and only then the write check. The source half of the
      // scope rule is already covered: requireAssetWriteScope above resolved
      // this Asset and asked for write scope on the Org Unit it sits at now.
      // Both halves are needed for the reason the parent-scope rule above
      // gives — being entitled to act on the Asset is not enough when a second
      // record changes with it, and here two Org Units do: one loses a machine
      // from its register and one gains one.
      if (hasOrgUnitId) {
        const orgUnitId = parseId(body.orgUnitId);
        if (orgUnitId === null) {
          return res.status(400).json({ message: 'orgUnitId must be a valid Org Unit id' });
        }
        const orgUnit = await people.findOrgUnit(orgUnitId);
        if (!orgUnit) throw notFound('Org Unit');

        const allowedOnDestination = await people.canAct({
          account: req.account,
          orgUnitId: orgUnit.id,
          write: true
        });
        if (!allowedOnDestination) {
          return res.status(403).json({ message: people.OUTSIDE_GRANTED_ORG_UNITS });
        }

        req.orgUnit = orgUnit;
      }

      let asset = req.asset;
      if (hasParentId) {
        asset = await assets.setAssetParent(req.params.id, body.parentId, req.account.id);
      }
      if (hasIsActive) {
        asset = await assets.setAssetActive(req.params.id, body.isActive, req.account.id);
      }
      if (hasOrgUnitId) {
        asset = await assets.setAssetOrgUnit(req.params.id, req.orgUnit.id, req.account.id);
      }

      res.json({ asset });
    } catch (error) {
      handleError(error, res, next);
    }
  }
);

module.exports = router;
