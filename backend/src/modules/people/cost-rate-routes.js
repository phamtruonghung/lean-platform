/*
 * The cost rate catalogue over HTTP (issue #252), mounted by index.js under
 * `/api/people` beside job-role-routes.js and skill-routes.js. See
 * cost-rates.js's header for what the catalogue is, why it lives in this
 * Module, and why the overlap and fallback rules stay in the database.
 *
 * Two access rules, deliberately different — the same asymmetry
 * job-role-routes.js and injury-type-routes.js already draw for their own
 * catalogues:
 *
 *   - `GET /cost-rates` and `GET /cost-rates/resolution` are open to any active
 *     Account. A rate is shared reference data (ADR-0005), and the resolution
 *     read is how a person finds out what a cost view will actually use — a
 *     number the tier board already shows them. Neither is Org-Unit scoped:
 *     Org Unit scope decides where an Account may *act*, not what it may know
 *     (ADR-0009).
 *   - Creating, correcting, closing and revising one are the administrator's.
 *     Rates are commercially sensitive and change rarely, so issue #252 takes
 *     ADR-0005's shared-catalogue shape rather than adding an authority to a
 *     Grant. There is no Org Unit to scope a catalogue write by, so the scope
 *     half of "existence before scope" is the role check.
 *
 * `requireAdmin` is defined here rather than imported from `./authorization`,
 * matching floor-routes.js's own local copy in this same Module and
 * injury-type-routes.js's in Safety. It adds one thing those do not: a stable
 * `code` beside the unchanged sentence, so a client can match the refusal
 * without matching its wording (issue #119's own reasoning for `httpError`'s
 * third argument, and issue #252's criterion that every write refusal carries
 * one).
 *
 * Existence before scope on every write (AGENTS.md §6): the cost rate named in
 * the URL is resolved first — a 404 naming it, malformed id included — and only
 * then is `requireAdmin` asked, so the same address answers 404 for a rate that
 * is not there and 403 for one that is.
 */

const express = require('express');
const { authenticate, requireActive } = require('./middleware');
const costRates = require('./cost-rates');
const { parseId, notFound, handleError } = require('./errors');

const router = express.Router();

// The machine-readable tag on the administrator refusal, shared verbatim with
// product-cost-routes.js's own copy — the two catalogues refuse identically.
const ADMIN_ROLE_REQUIRED = 'ADMIN_ROLE_REQUIRED';

function requireAdmin(req, res, next) {
  if (req.account.role !== 'admin') {
    return res.status(403).json({
      message: 'This action requires the administrator role.',
      code: ADMIN_ROLE_REQUIRED
    });
  }
  return next();
}

// The cost rate named in the URL must exist before anything else — a clean 404,
// even for an administrator, and even for a malformed id (`parseId` answers null
// for anything that is not a positive integer, and findCostRate is total: null
// and "no such row" are the same 404).
async function requireKnownCostRate(req, res, next) {
  try {
    const id = parseId(req.params.id);
    if (id === null) throw notFound('Cost rate');
    req.costRate = await costRates.findCostRate(id);
    return next();
  } catch (error) {
    return handleError(error, res, next);
  }
}

// The catalogue, history included: a closed period is what makes a historical
// cost reproducible, so the Screen shows every row with its effective dates
// rather than only what is current today.
router.get('/cost-rates', authenticate, requireActive, async (_req, res, next) => {
  try {
    res.json({ costRates: await costRates.listCostRates() });
  } catch (error) {
    handleError(error, res, next);
  }
});

// Everything a rate may be scoped to — Sites, Org Units, Assets and cost
// centres in one list, each carrying its own scope type. This is what makes the
// scope a *chosen* value rather than a typed id (ADR-0023); the catalogue's own
// form picks a scope here and the scopeType/scopeId pair falls out of the pick.
// Open to any active Account, like the catalogue itself.
router.get('/cost-rates/scopes', authenticate, requireActive, async (_req, res, next) => {
  try {
    res.json({ scopes: await costRates.listCostRateScopes() });
  } catch (error) {
    handleError(error, res, next);
  }
});

// What the cost views would actually resolve for one Org Unit (optionally one
// Asset within it) on one day. Registered before `/cost-rates/:id`-shaped routes
// would be a concern if any existed; there is no `GET /cost-rates/:id`, so
// `resolution` is an ordinary static path with nothing to collide with.
//
// The fallback rule is `resolve_cost_rate`'s and is called, not re-spelled —
// cost-rates.js's resolveCostRate is four lines of SQL around the function
// itself.
router.get('/cost-rates/resolution', authenticate, requireActive, async (req, res, next) => {
  try {
    const resolution = await costRates.resolveCostRate({
      orgUnitId: req.query.orgUnitId,
      assetId: req.query.assetId,
      rateType: req.query.rateType,
      at: req.query.at
    });
    res.json({ resolution });
  } catch (error) {
    handleError(error, res, next);
  }
});

// A rate is created with its scope, its rate type, its amount and the day it
// takes effect. An overlapping period is the one refusal this route can raise
// with no rate of its own to name, which is why it is mapped in the service
// (the EXCLUDE constraint's 23P01) rather than resolved here.
router.post('/cost-rates', authenticate, requireActive, requireAdmin, async (req, res, next) => {
  try {
    const costRate = await costRates.createCostRate(req.body ?? {}, req.account.id);
    res.status(201).json({ costRate });
  } catch (error) {
    handleError(error, res, next);
  }
});

// Correcting one in place: a mistyped amount, a wrong currency, a period that
// started on the wrong day — and closing it, by setting `effectiveTo`. Its
// scope and rate type are refused by the service rather than silently ignored.
// Recording a *new* amount from a date is the revision route below, not this.
router.patch(
  '/cost-rates/:id',
  authenticate,
  requireActive,
  requireKnownCostRate,
  requireAdmin,
  async (req, res, next) => {
    try {
      const costRate = await costRates.updateCostRate(
        req.costRate.id,
        req.body ?? {},
        req.account.id
      );
      res.json({ costRate });
    } catch (error) {
      handleError(error, res, next);
    }
  }
);

// The correction that actually happens in a plant: a new amount from a date,
// which closes the old row and opens a new one in one transaction. A route of
// its own rather than a flag on the PATCH above, for ADR-0019's reason — it is
// a different act with a different outcome (two rows, not one), and the answer
// names both so a caller can show what was closed and what replaced it.
router.post(
  '/cost-rates/:id/revision',
  authenticate,
  requireActive,
  requireKnownCostRate,
  requireAdmin,
  async (req, res, next) => {
    try {
      const { closed, opened } = await costRates.reviseCostRate(
        req.costRate.id,
        req.body ?? {},
        req.account.id
      );
      res.status(201).json({ closed, opened });
    } catch (error) {
      handleError(error, res, next);
    }
  }
);

module.exports = router;
