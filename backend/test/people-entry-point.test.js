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
 * Issue #251 adds a sixteenth, `kpiRegistry`: this Module's contribution to
 * the tier board (issue #202's composable registry), spread into the assembled
 * one at src/index.js. Dropping it would not break a require path anywhere —
 * `{ ...undefined }` is a legal spread — so the board would simply go back to
 * reporting `no_data` for both People KPIs with nothing failing to say so,
 * which is exactly the silent regression this file exists to catch. The same
 * reasoning `quality-entry-point.test.js` already records for its own.
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

test('the People Module entry point exposes exactly sixteen names', () => {
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
      'kpiRegistry',
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

// #251: the two People-pillar numbers confirmed attendance answers. Asserted
// at the same level as quality-entry-point.test.js's own — the codes claimed,
// the fields board.js reads off each entry, and the codes deliberately left
// unclaimed so the board keeps answering `no_data` for them.
test('kpiRegistry names the two People KPIs this Module computes, and nothing else', () => {
  assert.strictEqual(typeof people.kpiRegistry, 'object');
  assert.notStrictEqual(people.kpiRegistry, null);
  assert.deepStrictEqual(Object.keys(people.kpiRegistry).sort(), [
    'PPL_ABSENTEEISM',
    'PPL_HEADCOUNT'
  ]);

  // Both are period measures filed at an Org Unit, read from one derived table
  // over confirmed attendance sheets (people/kpi-registry.js's own header).
  for (const [code, entry] of Object.entries(people.kpiRegistry)) {
    assert.strictEqual(typeof entry.view, 'string', `${code} names its source`);
    assert.strictEqual(entry.dateColumn, 'production_date', `${code} is filed by production day`);
    assert.strictEqual(entry.orgUnitColumn, 'org_unit_id', `${code} is filed at an Org Unit`);
    // Neither carries board.js's `compute` escape hatch: these two use the
    // board's own period, where SAF_TRIR/SAF_LTIFR use a rolling window the
    // generic reader cannot express (ADR-0041, and this Module's own header).
    assert.strictEqual(entry.compute, undefined, `${code} needs no compute escape hatch`);
  }

  // Absenteeism is a ratio the board sums top and bottom of before dividing
  // once — never an average of per-day or per-Org-Unit percentages — and the
  // headcount is a plain column the board averages per confirmed shift
  // instance.
  assert.deepStrictEqual(people.kpiRegistry.PPL_ABSENTEEISM.ratio, {
    numerator: 'absent_headcount',
    denominator: 'scheduled_headcount',
    scale: 100
  });
  assert.strictEqual(people.kpiRegistry.PPL_ABSENTEEISM.valueColumn, undefined);
  assert.strictEqual(people.kpiRegistry.PPL_HEADCOUNT.valueColumn, 'present_headcount');
  assert.strictEqual(people.kpiRegistry.PPL_HEADCOUNT.ratio, undefined);

  // Left unclaimed on purpose (people/kpi-registry.js's own header):
  // PPL_OVERDUE_ACTIONS reads an Actions record rather than a People one,
  // COST_OVERTIME is the Cost pillar's reading of attendance and belongs to
  // #252, and PPL_SKILL_COVERAGE is not a number this ticket unblocked.
  for (const code of ['PPL_SKILL_COVERAGE', 'PPL_OVERDUE_ACTIONS', 'COST_OVERTIME', 'COST_LABOUR']) {
    assert.strictEqual(people.kpiRegistry[code], undefined, `${code} must stay no_data`);
  }
});

test('OUTSIDE_GRANTED_ORG_UNITS is the exact shared 403 wording', () => {
  assert.strictEqual(people.OUTSIDE_GRANTED_ORG_UNITS, "Outside the caller's granted Org Units");
});
