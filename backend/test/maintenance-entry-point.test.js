/*
 * The Maintenance Module's entry point (issue #56), asserted at the
 * export-set level — the same claim people-entry-point.test.js makes, for
 * the same reason: the boundary checker looks at require paths, not at what
 * an entry point actually hands back.
 *
 * One export today. Adding one is cheap when a second Module genuinely needs
 * an answer only Maintenance can give; re-exporting an internal so a sibling
 * ticket can skip a layer is what this test exists to make visible.
 */

const test = require('node:test');
const assert = require('node:assert');

const maintenance = require('../src/modules/maintenance');

test('the Maintenance Module entry point exposes exactly one name', () => {
  assert.deepStrictEqual(Object.keys(maintenance), ['router']);
});
