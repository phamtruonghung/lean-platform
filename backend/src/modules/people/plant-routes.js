/*
 * Sites and the Org Unit tree, over HTTP (issue #7). Mounted by index.js
 * alongside routes.js's Account surface, both under `/api/people` — see
 * that file's own note on why this belongs in the People Module rather
 * than a Module of its own.
 *
 * Every route here sits behind `authenticate` + `requireActive`, reads
 * included: role/scope enforcement (only an administrator may write) is
 * issue #8's, but nothing here is public to an unapproved Account either.
 * See plant.js's own header for that assumption stated once, in full.
 */

const express = require('express');
const { authenticate, requireActive } = require('./middleware');
const plant = require('./plant');

const router = express.Router();

// A domain error carries its own status (plant.js's httpError) and is the
// expected shape for a bad request, a missing id, or a conflict; anything
// else is a genuine failure and goes to the app's own unhandled-error
// handler via next().
function handleError(error, res, next) {
  if (error.status) {
    return res.status(error.status).json({ message: error.message });
  }
  return next(error);
}

router.post('/sites', authenticate, requireActive, async (req, res, next) => {
  try {
    const site = await plant.createSite(req.body ?? {}, req.account.id);
    res.status(201).json({ site });
  } catch (error) {
    handleError(error, res, next);
  }
});

router.get('/sites', authenticate, requireActive, async (_req, res, next) => {
  try {
    res.json({ sites: await plant.listSites() });
  } catch (error) {
    handleError(error, res, next);
  }
});

router.get('/sites/:siteId', authenticate, requireActive, async (req, res, next) => {
  try {
    res.json({ site: await plant.getSite(plant.parseId(req.params.siteId)) });
  } catch (error) {
    handleError(error, res, next);
  }
});

// GET /sites/:siteId/org-units             -> the Site's root Org Units
// GET /sites/:siteId/org-units?parentId=42 -> Org Unit 42's direct children
// One level per call, which is what "browsed from a Site down to a work
// centre" means here — see getOrgUnitSubtree below for "everything at once".
router.get('/sites/:siteId/org-units', authenticate, requireActive, async (req, res, next) => {
  try {
    const siteId = plant.parseId(req.params.siteId);
    let parentId;
    if (req.query.parentId !== undefined) {
      parentId = plant.parseId(req.query.parentId);
      if (parentId === null) {
        return res.status(400).json({ message: 'parentId must be a valid Org Unit id' });
      }
    }
    res.json({ orgUnits: await plant.listOrgUnits(siteId, parentId) });
  } catch (error) {
    handleError(error, res, next);
  }
});

router.post('/sites/:siteId/org-units', authenticate, requireActive, async (req, res, next) => {
  try {
    const siteId = plant.parseId(req.params.siteId);
    const orgUnit = await plant.createOrgUnit(siteId, req.body ?? {}, req.account.id);
    res.status(201).json({ orgUnit });
  } catch (error) {
    handleError(error, res, next);
  }
});

router.get('/org-units/:id', authenticate, requireActive, async (req, res, next) => {
  try {
    res.json({ orgUnit: await plant.getOrgUnit(plant.parseId(req.params.id)) });
  } catch (error) {
    handleError(error, res, next);
  }
});

// Everything beneath the given Org Unit, itself included, in one request —
// the issue's own acceptance criterion.
router.get('/org-units/:id/subtree', authenticate, requireActive, async (req, res, next) => {
  try {
    res.json({ orgUnits: await plant.getOrgUnitSubtree(plant.parseId(req.params.id)) });
  } catch (error) {
    handleError(error, res, next);
  }
});

// Deactivation, not deletion — the only field this route ever changes.
router.patch('/org-units/:id', authenticate, requireActive, async (req, res, next) => {
  try {
    if (typeof req.body?.isActive !== 'boolean') {
      return res.status(400).json({ message: 'isActive (boolean) is required' });
    }
    const orgUnit = await plant.setOrgUnitActive(
      plant.parseId(req.params.id),
      req.body.isActive,
      req.account.id
    );
    res.json({ orgUnit });
  } catch (error) {
    handleError(error, res, next);
  }
});

module.exports = router;
