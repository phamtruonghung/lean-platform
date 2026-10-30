/*
 * The KPI catalogue Module's entry point (ADR-0006, ADR-0055): exactly one name,
 * `router`, mounted under `/api/kpi`. What the routes do is proved over HTTP in
 * integration/kpi.test.js; this pins only the shape a caller can see without a
 * database.
 */

const test = require('node:test');
const assert = require('node:assert');

const kpi = require('../src/modules/kpi');

test('the KPI catalogue Module entry point exposes exactly one name', () => {
  assert.deepStrictEqual(Object.keys(kpi).sort(), ['router']);
});

test('router is a mountable Express router', () => {
  assert.strictEqual(typeof kpi.router, 'function');
  assert.strictEqual(typeof kpi.router.use, 'function');
  assert.strictEqual(typeof kpi.router.handle, 'function');
});

// Every other Module that reports a number contributes a `kpiRegistry` to the
// tier board. This one deliberately does not: the board's registry holds the
// Platform's own numbers, derived from records in the Platform's own database,
// and the MTU catalogue is a different set of numbers with no Platform records
// behind it. Merging the two is the mistake ADR-0055 exists to prevent.
test('there is no kpiRegistry: the MTU catalogue is a different set of numbers', () => {
  assert.strictEqual(kpi.kpiRegistry, undefined);
});
