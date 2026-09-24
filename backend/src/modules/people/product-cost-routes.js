/*
 * The product standard cost catalogue over HTTP (issue #252), mounted by
 * index.js under `/api/people` beside cost-rate-routes.js. See
 * product-costs.js's header for what the catalogue is and why it lives in this
 * Module, and cost-rate-routes.js's header for the two access rules — they are
 * the same two, for the same reasons, and the local `requireAdmin` below is
 * that file's copy verbatim (the per-file duplication injury-type-routes.js and
 * body-part-routes.js already keep for the Safety Module's pair).
 *
 * There is no resolution read here, deliberately: `product_standard_cost` has
 * no fallback rule to make visible, unlike `resolve_cost_rate`. See the note at
 * the foot of product-costs.js.
 */

const express = require('express');
const { authenticate, requireActive } = require('./middleware');
const productCosts = require('./product-costs');
const { parseId, notFound, handleError } = require('./errors');

const router = express.Router();

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

async function requireKnownProductCost(req, res, next) {
  try {
    const id = parseId(req.params.id);
    if (id === null) throw notFound('Product standard cost');
    req.productCost = await productCosts.findProductCost(id);
    return next();
  } catch (error) {
    return handleError(error, res, next);
  }
}

// The catalogue, history included — see cost-rate-routes.js's own GET.
router.get('/product-costs', authenticate, requireActive, async (_req, res, next) => {
  try {
    res.json({ productCosts: await productCosts.listProductCosts() });
  } catch (error) {
    handleError(error, res, next);
  }
});

// The Products a standard cost may be recorded against — the known set the
// catalogue's own form picks from (ADR-0023), and the counterpart of
// `GET /cost-rates/scopes`. Open to any active Account, like the catalogue.
router.get('/product-costs/products', authenticate, requireActive, async (_req, res, next) => {
  try {
    res.json({ products: await productCosts.listCostableProducts() });
  } catch (error) {
    handleError(error, res, next);
  }
});

// A standard cost is created with its Product, the cost, its currency and the
// day it takes effect.
router.post('/product-costs', authenticate, requireActive, requireAdmin, async (req, res, next) => {
  try {
    const productCost = await productCosts.createProductCost(req.body ?? {}, req.account.id);
    res.status(201).json({ productCost });
  } catch (error) {
    handleError(error, res, next);
  }
});

// Correcting one in place, and closing it by setting `effectiveTo`. Its Product
// is refused by the service rather than silently ignored.
router.patch(
  '/product-costs/:id',
  authenticate,
  requireActive,
  requireKnownProductCost,
  requireAdmin,
  async (req, res, next) => {
    try {
      const productCost = await productCosts.updateProductCost(
        req.productCost.id,
        req.body ?? {},
        req.account.id
      );
      res.json({ productCost });
    } catch (error) {
      handleError(error, res, next);
    }
  }
);

// A new cost from a date: closes the old row and opens a new one, in one
// transaction. See cost-rate-routes.js's own revision route for why this is a
// route rather than a flag.
router.post(
  '/product-costs/:id/revision',
  authenticate,
  requireActive,
  requireKnownProductCost,
  requireAdmin,
  async (req, res, next) => {
    try {
      const { closed, opened } = await productCosts.reviseProductCost(
        req.productCost.id,
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
