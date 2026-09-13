/*
 * Inventory over HTTP (issue #80): the parts catalogue, stores, and the stock
 * a store holds. Mounted by index.js under `/api/maintenance` alongside the
 * Asset, Work order, Request, Downtime, Job plan and PM schedule routers —
 * see inventory.js's own header for why Inventory lives inside Maintenance
 * rather than as a Module of its own (ADR-0006 clause 1, and the atomic
 * booking #75 needs).
 *
 * Like asset-routes.js, this is the one file in the pairing that talks to
 * People, and only through `modules/people`'s entry point (ADR-0006):
 * `authenticate`, `requireActive`, `findSite`, `findOrgUnit`, `canAct` and
 * the shared `OUTSIDE_GRANTED_ORG_UNITS` wording.
 *
 * Two scope rules, deliberately different, the same asymmetry ADR-0009 gives
 * the Asset register:
 *
 *   - Reads are Site-wide. `GET /sites/:siteId/stores`,
 *     `GET /stores/:storeId/stock` and `GET /stores/:storeId/movements` sit
 *     behind `authenticate` + `requireActive` and nothing else. Org Unit
 *     scope decides where an Account may act, not what it may know about, and
 *     "what is on the shelf" is a thing a supervisor plans around.
 *   - Writes are branch-scoped. Creating a store and recording a movement
 *     each require a write Grant reaching the relevant Org Unit.
 *
 * Every write resolves existence BEFORE asking about scope (issue #8's own
 * 403-vs-404 ordering): `canAct` returns true for role `admin` before it
 * checks whether the Org Unit id is null at all, so asking scope first would
 * turn an administrator's typo into a 500 on a NOT NULL foreign key rather
 * than a clean 404.
 *
 * `requireAdmin` is defined here rather than imported from People: People's
 * entry point deliberately does not export `requireAdmin`/`isAdmin` (see
 * people/index.js's own "deliberately NOT exported" list), so a Module outside
 * it carries its own copy of the role check, matching job-plan-routes.js's
 * copy and People's own refusal sentence word for word.
 */

const express = require('express');
const people = require('../people');
const inventory = require('./inventory');
const { parseId, notFound, handleError } = require('./errors');

const router = express.Router();

function requireAdmin(req, res, next) {
  if (req.account.role !== 'admin') {
    return res.status(403).json({ message: 'This action requires the administrator role.' });
  }
  return next();
}

// The Site a listing names must exist, whoever is asking — a 404, never a
// silently empty 200, the same answer asset-routes.js's requireKnownSite
// gives for its own Site-shaped read.
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

// Write scope on the Org Unit named in the body, when creating a store. The
// same rule asset-routes.js's requireOrgUnitWriteScope applies to an Asset's
// placement: resolve the Org Unit first (404), then ask about scope (403).
// `write: true` is passed explicitly and must stay that way — canAct's
// `write` defaults to FALSE, so dropping it would silently authorise this
// write for any read Grant, with no error anywhere to notice.
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

// The store named in the URL must exist before anything else — a clean 404,
// even for an administrator, and even for a malformed id (findStore is
// total). The message names the Store, so a caller who typed the wrong
// address can tell that from a scope refusal.
async function requireKnownStore(req, res, next) {
  try {
    const store = await inventory.findStore(req.params.storeId);
    if (!store) throw notFound('Store');
    req.store = store;
    return next();
  } catch (error) {
    return handleError(error, res, next);
  }
}

// Write scope on the Org Unit the STORE sits at, read off the store row
// rather than the URL or body. Runs after requireKnownStore has proven the
// store exists, so this is the existence-then-scope order. `write: true` is
// passed explicitly and must stay that way, for the reason
// requireOrgUnitWriteScope's own comment gives.
async function requireStoreWriteScope(req, res, next) {
  try {
    const allowed = await people.canAct({
      account: req.account,
      orgUnitId: req.store.orgUnitId,
      write: true
    });
    if (!allowed) {
      return res.status(403).json({ message: people.OUTSIDE_GRANTED_ORG_UNITS });
    }
    return next();
  } catch (error) {
    return handleError(error, res, next);
  }
}

// ---------------------------------------------------------------------------
// Parts — the shared catalogue.
// ---------------------------------------------------------------------------

// The unit picker's own list — active `units_of_measure` rows, readable by any
// approved Account. A value with a known set is chosen, never typed
// (ADR-0023), and this is the one catalogue that selection draws from, so
// nothing on the client has to hardcode a unit.
router.get('/units-of-measure', people.authenticate, people.requireActive, async (req, res, next) => {
  try {
    res.json({ unitsOfMeasure: await inventory.listUnitsOfMeasure() });
  } catch (error) {
    handleError(error, res, next);
  }
});

// Any approved Account reads the catalogue. Active parts only by default;
// `?includeInactive=true` is the deliberate way to widen, the same exact
// -string comparison job-plan-routes.js uses so garbage never silently
// widens the list.
router.get('/parts', people.authenticate, people.requireActive, async (req, res, next) => {
  try {
    const includeInactive = req.query.includeInactive === 'true';
    res.json({ parts: await inventory.listParts({ includeInactive }) });
  } catch (error) {
    handleError(error, res, next);
  }
});

// Defining a part is administrator-only, the same gate job-plan-routes.js and
// People's own job-role writes use: a part is a shared catalogue (ADR-0005),
// so there is no Org Unit in play to scope it to and no Grant to check.
router.post('/parts', people.authenticate, people.requireActive, requireAdmin, async (req, res, next) => {
  try {
    const part = await inventory.createPart(req.body ?? {}, req.account.id);
    res.status(201).json({ part });
  } catch (error) {
    handleError(error, res, next);
  }
});

// ---------------------------------------------------------------------------
// Stores.
// ---------------------------------------------------------------------------

router.get(
  '/sites/:siteId/stores',
  people.authenticate,
  people.requireActive,
  requireKnownSite,
  async (req, res, next) => {
    try {
      const includeInactive = req.query.includeInactive === 'true';
      res.json({ stores: await inventory.listStoresAtSite(req.site.id, { includeInactive }) });
    } catch (error) {
      handleError(error, res, next);
    }
  }
);

// Creating a store names the Org Unit it sits at; the Site is derived from
// that Org Unit rather than sent, so the two can never disagree. Scope is
// checked on the named Org Unit.
router.post(
  '/stores',
  people.authenticate,
  people.requireActive,
  requireOrgUnitWriteScope,
  async (req, res, next) => {
    try {
      const store = await inventory.createStore(
        {
          ...(req.body ?? {}),
          siteId: req.orgUnit.siteId,
          orgUnitId: req.orgUnit.id
        },
        req.account.id
      );
      res.status(201).json({ store });
    } catch (error) {
      handleError(error, res, next);
    }
  }
);

// ---------------------------------------------------------------------------
// Stock, read as the derived level and the movements it is derived from.
// ---------------------------------------------------------------------------

// One store's own row, so the stock Screen can name the shelf it is showing
// without a second read of the whole Site's list.
router.get(
  '/stores/:storeId',
  people.authenticate,
  people.requireActive,
  requireKnownStore,
  async (req, res, next) => {
    try {
      res.json({ store: req.store });
    } catch (error) {
      handleError(error, res, next);
    }
  }
);

router.get(
  '/stores/:storeId/stock',
  people.authenticate,
  people.requireActive,
  requireKnownStore,
  async (req, res, next) => {
    try {
      res.json({ store: req.store, stock: await inventory.listStockForStore(req.store.id) });
    } catch (error) {
      handleError(error, res, next);
    }
  }
);

router.get(
  '/stores/:storeId/movements',
  people.authenticate,
  people.requireActive,
  requireKnownStore,
  async (req, res, next) => {
    try {
      res.json({ movements: await inventory.listMovementsForStore(req.store.id) });
    } catch (error) {
      handleError(error, res, next);
    }
  }
);

// ---------------------------------------------------------------------------
// Movements: a receipt is in, an adjustment is either way. Both need a write
// Grant reaching the store's Org Unit.
// ---------------------------------------------------------------------------

router.post(
  '/stores/:storeId/receipts',
  people.authenticate,
  people.requireActive,
  requireKnownStore,
  requireStoreWriteScope,
  async (req, res, next) => {
    try {
      const result = await inventory.receiveStock(req.store.id, req.body ?? {}, req.account.id);
      res.status(201).json(result);
    } catch (error) {
      handleError(error, res, next);
    }
  }
);

router.post(
  '/stores/:storeId/adjustments',
  people.authenticate,
  people.requireActive,
  requireKnownStore,
  requireStoreWriteScope,
  async (req, res, next) => {
    try {
      const result = await inventory.adjustStock(req.store.id, req.body ?? {}, req.account.id);
      res.status(201).json(result);
    } catch (error) {
      handleError(error, res, next);
    }
  }
);

module.exports = router;
