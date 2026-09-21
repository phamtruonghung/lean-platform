/*
 * The People Module's entry point (issue #59, widened by issue #201),
 * asserted at the export-set level rather than the require-path level.
 * `npm run lint`'s module boundary checker only ever looks at require *paths*
 * — it proves a Module cannot reach past another Module's entry point, not
 * that the entry point itself still hands back what its consumers need — and
 * nothing else in this suite consumes `modules/people`'s exports at all.
 * Without this test, dropping `canAct` (or any of the other names) from
 * index.js would go unnoticed here until it broke Maintenance (#56, #57, #61,
 * #62, #63, off parent #55) or a floor route (#77, #201), which each depend on
 * a specific subset of this list — see index.js's own header for which ticket
 * needs which export and why.
 *
 * Issue #201 adds five names: the shared floor device and the identification
 * an Employee presents on it moved into this Module, so `floorRouter` (mounted
 * by src/index.js at the frozen `/api/maintenance` prefix rather than under
 * `/api/people`) and the four lookups Maintenance's floor door asks —
 * findDeviceByCredential, findDeviceContext, findValidIdentification and
 * deviceReachesOrgUnit. The four are questions returning a value, which is the
 * shape ADR-0006's first two clauses require; the router is the documented
 * control-flow exception `router` already is.
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

test('the People Module entry point exposes exactly fifteen names', () => {
  assert.deepStrictEqual(
    Object.keys(people).sort(),
    [
      'OUTSIDE_GRANTED_ORG_UNITS',
      'authenticate',
      'canAct',
      'canSeeSite',
      'deviceReachesOrgUnit',
      'findDeviceByCredential',
      'findDeviceContext',
      'findEmployee',
      'findOrgUnit',
      'findValidIdentification',
      'findSite',
      'safetyAuthorityOrgUnitIds',
      'floorRouter',
      'requireActive',
      'router'
    ].sort()
  );
});

test('canAct, canSeeSite, findOrgUnit, findSite, findEmployee, authenticate, requireActive are functions', () => {
  assert.strictEqual(typeof people.canAct, 'function');
  // #198: raising a Concern asks about a whole Site rather than one Org Unit,
  // so modules/actions needs this one as well as canAct.
  assert.strictEqual(typeof people.canSeeSite, 'function');
  assert.strictEqual(typeof people.findOrgUnit, 'function');
  assert.strictEqual(typeof people.findSite, 'function');
  assert.strictEqual(typeof people.findEmployee, 'function');
  assert.strictEqual(typeof people.authenticate, 'function');
  assert.strictEqual(typeof people.requireActive, 'function');
});

// #224, ADR-0037: the Safety Module asks which Org Units in a Site a Grant
// carrying Safety authority reaches, so that an injured person's diagnosis is
// withheld from every other caller — an administrator holding no such Grant
// included, which is exactly why this is a separate question from
// `canAct({ safety: true })` rather than another option on it. See
// authorization.js's own comment above the function.
test('safetyAuthorityOrgUnitIds is a function, and is not canAct', () => {
  assert.strictEqual(typeof people.safetyAuthorityOrgUnitIds, 'function');
  assert.notStrictEqual(people.safetyAuthorityOrgUnitIds, people.canAct);
});

test('the four floor lookups another Module asks through this entry point are functions', () => {
  assert.strictEqual(typeof people.findDeviceByCredential, 'function');
  assert.strictEqual(typeof people.findDeviceContext, 'function');
  assert.strictEqual(typeof people.findValidIdentification, 'function');
  assert.strictEqual(typeof people.deviceReachesOrgUnit, 'function');
});

// A router, not a route file inside `router`: src/index.js mounts `floorRouter`
// at the frozen `/api/maintenance` prefix the shared floor device has always
// called (issue #201). Folding it into `router` would move those URLs under
// `/api/people` and break every device in the field, so the two are asserted
// separately — the same way `router` itself is a mount target rather than a
// callable answer.
test('floorRouter and router are distinct mountable routers', () => {
  assert.strictEqual(typeof people.floorRouter, 'function');
  assert.notStrictEqual(people.floorRouter, people.router);
});

test('OUTSIDE_GRANTED_ORG_UNITS is the exact shared 403 wording', () => {
  assert.strictEqual(people.OUTSIDE_GRANTED_ORG_UNITS, "Outside the caller's granted Org Units");
});
