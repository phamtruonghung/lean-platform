/*
 * The Customer catalogue over HTTP (issue #214), mounted by index.js under
 * `/api/quality` beside product-routes.js and defect-code-routes.js.
 *
 * Two access rules, deliberately different — the same asymmetry ADR-0009 gives
 * the Asset register and product-routes.js gives the Product catalogue:
 *
 *   - Reads are open to any approved Account: "any active Account can search
 *     Customers" is the ticket's own criterion. `GET /customers` sits behind
 *     `authenticate` + `requireActive` and nothing else, because a Customer is
 *     shared reference data (ADR-0005) and the complaint form has to be able to
 *     offer the list to whoever is recording one.
 *   - Writes are the administrator's: "Customer writes are administrator-only"
 *     is the ticket's other criterion, and this is the whole of that rule —
 *     defining a Customer, correcting its name or its contact address and
 *     deactivating or reactivating it are the acts that decide what the
 *     customer list says, the same rule the Product catalogue and the job role
 *     catalogue follow.
 *
 * `requireAdmin` is defined here rather than imported from People or from
 * product-routes.js: People's entry point deliberately does not export
 * `requireAdmin`/`isAdmin`, and each route file in this Module carries its own
 * copy — matching product-routes.js's and defect-code-routes.js's copies and
 * People's own refusal sentence word for word.
 *
 * Existence before scope on every write (AGENTS.md §6): the Customer named in
 * the URL is resolved first — a 404 naming it, malformed id included — and only
 * then is `requireAdmin` asked, so the same address answers 404 for a Customer
 * that is not there and 403 for one that is. A Customer is not Org-Unit scoped,
 * so the scope half of that ordering is the role check rather than `canAct`;
 * the order itself is the convention.
 */

const express = require('express');
const people = require('../people');
const customers = require('./customers');
const { parseId, notFound, handleError } = require('./errors');

const router = express.Router();

function requireAdmin(req, res, next) {
  if (req.account.role !== 'admin') {
    return res.status(403).json({ message: 'This action requires the administrator role.' });
  }
  return next();
}

// The Customer named in the URL must exist before anything else — a clean 404,
// even for an administrator, and even for a malformed id (`parseId` answers
// null for anything that is not a positive integer, and findCustomer is total:
// null and "no such row" are the same 404).
async function requireKnownCustomer(req, res, next) {
  try {
    const id = parseId(req.params.id);
    if (id === null) throw notFound('Customer');
    req.customer = await customers.findCustomer(id);
    return next();
  } catch (error) {
    return handleError(error, res, next);
  }
}

// The list, and the search the ticket's own criterion names. Active Customers
// only unless the caller asks for the retired ones by exact string 'true' —
// never a stray or malformed value, which would silently widen the list past
// "who we still trade with". `?search=` matches code or name.
router.get('/customers', people.authenticate, people.requireActive, async (req, res, next) => {
  try {
    const includeInactive = req.query.includeInactive === 'true';
    const search = typeof req.query.search === 'string' ? req.query.search : undefined;
    res.json({ customers: await customers.listCustomers({ search, includeInactive }) });
  } catch (error) {
    handleError(error, res, next);
  }
});

// A Customer is created with its code, its name and an optional contact
// address. A code that is already taken is a 409, and that clash is the one
// refusal this route can raise with no Customer to name — which is why it is
// mapped in the service rather than resolved here.
router.post(
  '/customers',
  people.authenticate,
  people.requireActive,
  requireAdmin,
  async (req, res, next) => {
    try {
      const customer = await customers.createCustomer(req.body ?? {}, req.account.id);
      res.status(201).json({ customer });
    } catch (error) {
      handleError(error, res, next);
    }
  }
);

// Correcting a Customer: its name, its contact address, and whether it is still
// traded with. Its code is refused by customers.js rather than silently
// ignored.
router.patch(
  '/customers/:id',
  people.authenticate,
  people.requireActive,
  requireKnownCustomer,
  requireAdmin,
  async (req, res, next) => {
    try {
      const customer = await customers.updateCustomer(
        req.customer.id,
        req.body ?? {},
        req.account.id
      );
      res.json({ customer });
    } catch (error) {
      handleError(error, res, next);
    }
  }
);

module.exports = router;
