/*
 * The Maintenance Module's entry point (issue #56), asserted at the
 * export-set level — the same claim people-entry-point.test.js makes, for
 * the same reason: the boundary checker looks at require paths, not at what
 * an entry point actually hands back.
 *
 * One export today. Adding one is cheap when a second Module genuinely needs
 * an answer only Maintenance can give; re-exporting an internal so a sibling
 * ticket can skip a layer is what this test exists to make visible.
 *
 * Issue #201 moved the shared floor device and the identification presented on
 * it into the people Module and deliberately changed NOTHING here: this Module
 * is the consumer of that surface, not a provider of it — `work-order-routes.js`
 * and `floor-routes.js` ask `people.findDeviceByCredential`,
 * `people.findValidIdentification` and `people.deviceReachesOrgUnit` through
 * People's entry point, and no other Module asks Maintenance anything about a
 * device. So the set stays exactly one name, and its staying is the assertion
 * that nothing was smuggled out to make the move compile.
 */

const test = require('node:test');
const assert = require('node:assert');

const maintenance = require('../src/modules/maintenance');

test('the Maintenance Module entry point exposes exactly one name', () => {
  assert.deepStrictEqual(Object.keys(maintenance), ['router']);
});
