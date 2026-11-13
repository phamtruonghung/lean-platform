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
 *     `authenticate` + `requireActive` and `QLT_PRODUCTS_DISPLAY`: a Product is
 *     shared reference data (ADR-0005, one catalogue many plants), so where an
 *     Account may act has nothing to do with what it may know about being
 *     built. A later Quality slice needs this list as a set of choices
 *     (ADR-0023), which is a read whoever is recording the problem.
 *   - Writes ask the catalogue's own code. Creating a Product, correcting its
 *     name and deactivating or reactivating it ask `QLT_PRODUCTS_CHANGE`, the
 *     same rule job-plan-routes.js's catalogue writes follow. That code is
 *     seeded on ROLE_ADMIN alone — the exact set the administrator check it
 *     replaces admitted — and an administrator answers every permission true
 *     before any role is read (ADR-0061), so this is a retrofit rather than a
 *     new decision: no Account gains or loses access, and the refusal names the
 *     permission instead of the role. The act is still the administrator's; it
 *     is a code an administrator can grant later rather than a role this route
 *     spells out.
 *
 * `QLT_PRODUCTS_DISPLAY` is seeded on ROLE_STANDARD — the default group every
 * approved Account carries — so the read gate refuses nobody who could reach
 * this list before the retrofit. A permission says *what*, a Grant says *where*
 * (ADR-0061): the read stays open to any approved Account because a Product is
 * shared reference data (ADR-0005).
 *
 * Existence before scope on every write (AGENTS.md §6): the Product named in
 * the URL is resolved first — a 404 naming it, malformed id included, exactly
 * as requireKnownStore does for a Store — and only then is
 * `QLT_PRODUCTS_CHANGE` asked, so the same address answers 404 for a Product
 * that is not there and 403 for one that is. A Product is not Org-Unit scoped
 * (products.js's own header), so the scope half of that ordering is the
 * permission rather than `canAct`; the order itself is the convention.
 */

const express = require('express');
const people = require('../people');
const products = require('./products');
const { parseId, notFound, handleError } = require('./errors');

const router = express.Router();

// The two codes this catalogue asks (ADR-0061, issue #503). Both are answered
// from `roles.effectivePermissions` on every request, never cached, so an
// administrator's edit takes effect on the affected Account's next call.
const mayReadProducts = people.requirePermission('QLT_PRODUCTS_DISPLAY');
const mayChangeProducts = people.requirePermission('QLT_PRODUCTS_CHANGE');

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
router.get(
  '/products',
  people.authenticate,
  people.requireActive,
  mayReadProducts,
  async (req, res, next) => {
    try {
      const includeInactive = req.query.includeInactive === 'true';
      const search = typeof req.query.search === 'string' ? req.query.search : undefined;
      res.json({ products: await products.listProducts({ search, includeInactive }) });
    } catch (error) {
      handleError(error, res, next);
    }
  }
);

// A Product is created with its code, its name and the unit of measure it is
// measured in. The unit is a choice from `units_of_measure` (ADR-0023) and an
// unknown one is a 400 from products.js, not a raw foreign key failure. A code
// that is already taken is a 409, and that clash is the one refusal this route
// can raise with no Product to name — which is why it is mapped in the service
// rather than resolved here.
router.post(
  '/products',
  people.authenticate,
  people.requireActive,
  mayChangeProducts,
  async (req, res, next) => {
    try {
      const product = await products.createProduct(req.body ?? {}, req.account.id);
      res.status(201).json({ product });
    } catch (error) {
      handleError(error, res, next);
    }
  }
);

// Correcting a Product: its name, and whether it is still in use. Its code and
// its unit of measure are refused by products.js rather than silently ignored.
router.patch(
  '/products/:id',
  people.authenticate,
  people.requireActive,
  requireKnownProduct,
  mayChangeProducts,
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
