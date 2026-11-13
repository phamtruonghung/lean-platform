/*
 * Which reads carry no permission code, and why — the register ADR-0061 §7
 * writes, checked against the routers themselves.
 *
 * Why this file exists. The retrofit asked every read the same question — which
 * code names this door? — and found a class of address where the honest answer
 * is "none": a catalogue or a Site list several Screens legitimately read. In
 * each slice that read was left on its standing and recorded as a finding, so
 * the rule lives in prose (ADR-0061 §7) and nothing but review stops the next
 * one from being left ungated by accident, or from quietly gaining a code that
 * refuses a Screen nobody thought was connected to it. Both directions fail
 * here, because the expected set is written down and compared exactly.
 *
 * How it works. It asks the Module routers themselves — the Express layer stack
 * after `router.use` composition, the same object a request is matched against
 * — rather than grepping the source. A route registered through any spelling
 * (`router.get`, `router.route(...).get`) is a layer, so nothing can be added in
 * a shape this file cannot see, and a middleware counts as a gate exactly when
 * it is `requirePermission`'s own returned function or a `may…` alias of it.
 *
 * Why it is here and not under test/integration. It touches no database and no
 * HTTP surface, and `npm test` is the gate every change runs; the integration
 * suite is the other half of the evidence (role matrices against a real
 * database, in the per-Module `*-permission-roles.test.js` files). The same
 * reason module-boundaries.test.js sits beside it: a rule checked against the
 * source tree, not against a running server.
 *
 * The mount table below mirrors src/index.js, which cannot be required here: it
 * starts listening at import time. A Module mounted there and missing here
 * would be invisible to the census, so adding one is a two-line change in both
 * files — the same duplication `src/index.js` already accepts for its Modules.
 */

const test = require('node:test');
const assert = require('node:assert');
const express = require('express');

const people = require('../src/modules/people');
const maintenance = require('../src/modules/maintenance');
const actions = require('../src/modules/actions');
const quality = require('../src/modules/quality');
const safety = require('../src/modules/safety');
const production = require('../src/modules/production');
const kpi = require('../src/modules/kpi');

// Every GET a Module router answers with no permission code, exactly as
// ADR-0061 §7 writes it down. Grouped by the reason the ADR gives, in the same
// order; the comparison is on the set, so the grouping is for the reader.
const UNCODED_GETS = [
  // Shared reference data — the rule, and the reason the read stays open.
  'GET /api/people/timezones',
  'GET /api/people/sites',
  'GET /api/people/sites/:siteId',
  'GET /api/people/sites/:siteId/org-units',
  'GET /api/people/sites/:siteId/org-units/search',
  'GET /api/people/org-units/:id',
  'GET /api/people/org-units/:id/subtree',
  'GET /api/people/cost-rates',
  'GET /api/people/cost-rates/scopes',
  'GET /api/people/cost-rates/resolution',
  'GET /api/people/product-costs',
  'GET /api/people/product-costs/products',
  'GET /api/maintenance/sites/:siteId/assets',
  // Registered twice — meter-routes.js and inventory-routes.js each answer this
  // one address, which is why it appears twice on both sides of the comparison.
  'GET /api/maintenance/units-of-measure',
  'GET /api/maintenance/units-of-measure',
  'GET /api/maintenance/parts',
  'GET /api/maintenance/sites/:siteId/stores',
  'GET /api/maintenance/stores/:storeId',
  'GET /api/maintenance/stores/:storeId/stock',
  'GET /api/maintenance/stores/:storeId/movements',
  'GET /api/maintenance/job-plans',
  'GET /api/maintenance/job-plans/:id',
  'GET /api/safety/injury-types',
  'GET /api/safety/body-parts',

  // Module-owned reads whose code is still outstanding — named here so the
  // register above is not read as approval of them (ADR-0061 §7, second list).
  'GET /api/people/accounts',
  'GET /api/people/accounts/pending',

  // Not a door a code could ever name: the caller's own identity, the sign-in
  // mode a client asks about before it has a session, and the shared floor
  // device's reads (ADR-0016 — `requireFloorDevice`, not an Account).
  'GET /api/people/me',
  'GET /api/auth/mode',
  'GET /api/maintenance/floor/training/to-confirm',
  'GET /api/maintenance/floor/signature',
  'GET /api/maintenance/floor/work-orders',
  'GET /api/quality/floor/products',
  'GET /api/quality/floor/defect-codes'
];

// The composition src/index.js performs, in the same order. A plain object
// stands in for the KPI registry: the board router only reads it per request.
const MOUNTS = [
  ['/api/people', people.router],
  ['/api/auth', people.authRouter],
  ['/api/maintenance', people.floorRouter],
  ['/api/maintenance', maintenance.router],
  ['/api/maintenance', maintenance.createBoardRouter({})],
  ['/api/actions', actions.router],
  ['/api/quality', quality.router],
  ['/api/safety', safety.router],
  ['/api/production', production.router],
  ['/api/kpi', kpi.router]
];

function joinPath(prefix, path) {
  const joined = `${prefix}${path}`;
  return joined.length > 1 ? joined.replace(/\/+$/, '') : joined;
}

// A route's middleware is a gate when it is `requirePermission`'s own function
// (Express keeps the function's name) or a `may…` alias wrapping it. Everything
// else — authenticate, requireActive, requireAdmin, requireFloorDevice,
// requireKnownSite and the per-route visibility checks — answers a different
// question and is not a permission code.
function hasPermissionCode(layers) {
  return layers.some((layer) => {
    const name = (layer.handle && layer.handle.name) || '';
    return name === 'requirePermissionMiddleware' || /^may[A-Z]/.test(name);
  });
}

function censusGets(router, prefix = '') {
  const found = [];

  function walk(current, base, depth) {
    for (const layer of current.stack || []) {
      if (layer.route) {
        const isGet = Object.keys(layer.route.methods || {}).includes('get');
        if (!isGet) continue;
        if (hasPermissionCode(layer.route.stack || [])) continue;
        found.push(`GET ${joinPath(base, layer.route.path)}`);
      } else if (layer.handle && layer.handle.stack && depth < 5) {
        // A router mounted with a path keeps it in `layer.path`; the Module
        // entry points mount theirs at the root, but the walk does not rely
        // on that.
        const mount = typeof layer.path === 'string' && layer.path !== '/' ? layer.path : '';
        walk(layer.handle, joinPath(base, mount), depth + 1);
      }
    }
  }

  walk(router, prefix, 0);
  return found.sort();
}

test('every GET with no permission code is the register ADR-0061 §7 writes', () => {
  const found = MOUNTS.flatMap(([prefix, router]) => censusGets(router, prefix));

  assert.deepStrictEqual(
    found.slice().sort(),
    UNCODED_GETS.slice().sort(),
    'A GET with no permission code differs from ADR-0061 §7\'s register: ' +
      'either a new ungated read was added (write down why it is shared, or give it a code) ' +
      'or a listed route gained one (remove it from the register and from the ADR).'
  );
});

test('the census reports an ungated GET, and skips a gated one', () => {
  const fake = express.Router();
  fake.get('/open', (_req, res) => res.end());
  fake.get('/gated', people.authenticate, people.requirePermission('PPL_DIRECTORY_DISPLAY'), (_req, res) => res.end());

  assert.deepStrictEqual(censusGets(fake, '/api/fake'), ['GET /api/fake/open']);
});

test('a GET added with no code joins the census, so it cannot pass unrecorded', () => {
  const fake = express.Router();
  fake.get('/open', (_req, res) => res.end());

  const before = censusGets(fake, '/api/fake');
  fake.get('/added-later', (_req, res) => res.end());
  const after = censusGets(fake, '/api/fake');

  assert.deepStrictEqual(before, ['GET /api/fake/open']);
  assert.deepStrictEqual(after, ['GET /api/fake/added-later', 'GET /api/fake/open']);
  assert.notDeepStrictEqual(after, UNCODED_GETS.filter((route) => route.startsWith('GET /api/fake')));
});
