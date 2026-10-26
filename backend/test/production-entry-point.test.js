/*
 * The Production Module's entry point (ADR-0006, issue #340): exactly the two
 * names src/index.js needs — `router`, mounted under `/api/production`, and
 * `kpiRegistry`, spread into the tier board's registry. What each registry
 * entry computes is proved over HTTP in integration/handover-kpis.test.js;
 * this pins only the shape a caller can see without a database.
 */

const test = require('node:test');
const assert = require('node:assert');

const production = require('../src/modules/production');

test('the Production Module entry point exposes exactly two names', () => {
  assert.deepStrictEqual(Object.keys(production).sort(), ['kpiRegistry', 'router']);
});

test('router is a mountable Express router', () => {
  assert.strictEqual(typeof production.router, 'function');
  assert.strictEqual(typeof production.router.use, 'function');
  assert.strictEqual(typeof production.router.handle, 'function');
});

// Both entries own their whole computation — a median and a `now()` cut on the
// denominator are not something board.js's generic `{ view, ratio }` reader
// can express — so each carries `compute` and nothing the generic reader uses.
test('kpiRegistry names the two handover KPIs, each computing its own value', () => {
  assert.deepStrictEqual(Object.keys(production.kpiRegistry).sort(), [
    'PRO_HANDOVER_ACK_MINUTES',
    'PRO_HANDOVER_COMPLETION'
  ]);
  for (const [code, entry] of Object.entries(production.kpiRegistry)) {
    assert.strictEqual(typeof entry.compute, 'function', `${code} carries compute`);
    assert.strictEqual(entry.view, undefined, `${code} names no view for the generic reader`);
  }
});
