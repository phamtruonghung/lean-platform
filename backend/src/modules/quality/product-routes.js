/*
 * The Product catalogue over HTTP (issue #203), mounted by index.js under
 * `/api/quality` — the Quality Module's own prefix, beside `/api/people`,
 * `/api/maintenance` and `/api/actions`. See index.js's header for why this
 * Module exists and what it exports to whom.
 *
 * Two access rules, deliberately different — the same asymmetry ADR-0009 gives
 * the Asset register and job-role-routes.js gives the job role catalogue:
 *
 *   - Reads are open to any approved Account. `GET /products` sits behind
 *     `authenticate` + `requireActive` and nothing else: a Product is shared
 *     reference data (ADR-0005, one catalogue many plants), so where an
 *     Account may act has nothing to do with what it may know about being
 *     built. A later Quality slice needs this list as a set of choices
 *     (ADR-0023), which is a read whoever is recording the problem.
 *   - Writes are the administrator's. Creating a Product, correcting its name
 *     and deactivating or reactivating it are the acts that decide what the
 *     plant's catalogue says, the same rule job-plan-routes.js's catalogue
 *     writes follow.
 *
 * `requireAdmin` is defined here rather than imported from People: People's
 * entry point deliberately does not export `requireAdmin`/`isAdmin` (see
 * people/index.js's own "deliberately NOT exported" list), so a Module outside
 * it carries its own copy, matching inventory-routes.js's and
 * job-plan-routes.js's copies and People's own refusal sentence word for word.
 *
 * Existence before scope on every write (AGENTS.md §6): the Product named in
 * the URL is resolved first — a 404 naming it, malformed id included, exactly
 * as requireKnownStore does for a Store — and only then is `requireAdmin`
 * asked, so the same address answers 404 for a Product that is not there and
 * 403 for one that is. A Product is not Org-Unit scoped (products.js's own
 * header), so the scope half of that ordering is the role check rather than
 * `canAct`; the order itself is the convention.
 */

const express = require('express');
const people = require('../people');
const products = require('./products');
const { parseId, notFound, handleError } = require('./errors');

const router = express.Router();

function requireAdmin(req, res, next) {
  if (req.account.role !== 'admin') {
    return res.status(403).json({ message: 'This action requires the administrator role.' });
  }
  return next();
}

// The Product named in the URL must exist before anything else — a clean 404,
// even for an administrator, and even for a malformed id (`parseId` answers
// null for anything that is not a positive integer, and findProduct is total:
// null and "no such row" are the same 404).
async function requireKnownProduct(req, res, next) {
  try {
    const id = parseId(req.params.id);
    if (id === null) throw notFound('Product');
    req.product = await products.findProduct(id);
    return next();
  } catch (error) {
    return handleError(error, res, next);
  }
}

// The catalogue. Active Products only unless the caller asks for the retired
// ones by exact string 'true' — never a stray or malformed value, which would
// silently widen the list past "in use" (job-role-routes.js's own
// includeInactive reasoning). `?search=` matches code or name, so a caller
// holding either can find the Product they mean.
router.get('/products', people.authenticate, people.requireActive, async (req, res, next) => {
  try {
    const includeInactive = req.query.includeInactive === 'true';
    const search = typeof req.query.search === 'string' ? req.query.search : undefined;
    res.json({ products: await products.listProducts({ search, includeInactive }) });
  } catch (error) {
    handleError(error, res, next);
  }
});

// A Product is created with its code, its name and the unit of measure it is
// measured in. The unit is a choice from `units_of_measure` (ADR-0023) and an
// unknown one is a 400 from products.js, not a raw foreign key failure. A code
// that is already taken is a 409, and that clash is the one refusal this route
// can raise with no Product to name — which is why it is mapped in the service
// rather than resolved here.
router.post('/products', people.authenticate, people.requireActive, requireAdmin, async (req, res, next) => {
  try {
    const product = await products.createProduct(req.body ?? {}, req.account.id);
    res.status(201).json({ product });
  } catch (error) {
    handleError(error, res, next);
  }
});

// Correcting a Product: its name, and whether it is still in use. Its code and
// its unit of measure are refused by products.js rather than silently ignored.
router.patch(
  '/products/:id',
  people.authenticate,
  people.requireActive,
  requireKnownProduct,
  requireAdmin,
  async (req, res, next) => {
    try {
      const product = await products.updateProduct(req.product.id, req.body ?? {}, req.account.id);
      res.json({ product });
    } catch (error) {
      handleError(error, res, next);
    }
  }
);

module.exports = router;
