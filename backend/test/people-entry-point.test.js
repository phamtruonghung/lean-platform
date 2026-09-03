/*
 * The People Module's entry point (issue #59), asserted at the export-set
 * level rather than the require-path level. `npm run lint`'s module boundary
 * checker only ever looks at require *paths* — it proves a Module cannot
 * reach past another Module's entry point, not that the entry point itself
 * still hands back what its consumers need — and nothing else in this suite
 * consumes `modules/people`'s exports at all. Without this test, dropping
 * `canAct` (or any of the other six) from index.js would go unnoticed here
 * until it broke Maintenance (#56, #57, #61, #62, #63, off parent #55),
 * which each depend on a specific subset of this list — see index.js's own
 * header for which ticket needs which export and why.
 *
 * Needs no database: `getPool()` (platform/db.js) is lazy, so simply
 * requiring the Module and inspecting its export shape never opens a
 * connection.
 *
 * Adding an entry here is cheap — a new sibling Module needing one more
 * question answered is exactly what ADR-0006's "What a Module's entry point
 * may expose" section anticipates. Removing one, or narrowing what it
 * returns, is not: it breaks whichever named Module already depends on it,
 * silently, since nothing else in this backend calls through
 * `modules/people` today.
 */

const test = require('node:test');
const assert = require('node:assert');

const people = require('../src/modules/people');

test('the People Module entry point exposes exactly seven names', () => {
  assert.deepStrictEqual(
    Object.keys(people).sort(),
    ['OUTSIDE_GRANTED_ORG_UNITS', 'authenticate', 'canAct', 'findEmployee', 'findOrgUnit', 'requireActive', 'router'].sort()
  );
});

test('canAct, findOrgUnit, findEmployee, authenticate, requireActive are functions', () => {
  assert.strictEqual(typeof people.canAct, 'function');
  assert.strictEqual(typeof people.findOrgUnit, 'function');
  assert.strictEqual(typeof people.findEmployee, 'function');
  assert.strictEqual(typeof people.authenticate, 'function');
  assert.strictEqual(typeof people.requireActive, 'function');
});

test('OUTSIDE_GRANTED_ORG_UNITS is the exact shared 403 wording', () => {
  assert.strictEqual(people.OUTSIDE_GRANTED_ORG_UNITS, "Outside the caller's granted Org Units");
});
